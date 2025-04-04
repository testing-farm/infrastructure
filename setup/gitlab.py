#!/usr/bin/env python

#
# Implements utility functions for GitLab.
#

import os
import re
import sys
from datetime import datetime

import git.exc
import requests
import typer
from git import Actor, Repo
from requests.adapters import HTTPAdapter
from typing import NoReturn, Optional
from urllib3 import Retry

GITLAB_DOMAIN = os.getenv('CI_SERVER_HOST', 'gitlab.com')
PROJECT_ID = os.getenv('CI_PROJECT_ID', '17754827')
GITLAB_TOKEN = os.getenv('GITLAB_PRIVATE_TOKEN') or os.getenv('CI_JOB_TOKEN')

GITLAB_API_URL = f"https://{GITLAB_DOMAIN}/api/v4"

USER_NAME = 'Testing Farm Bot'
USER_EMAIL = 'tft@redhat.com'

DEFAULT_MR_BRANCH = f"gitlab-ci-{datetime.now().strftime('%Y-%m-%d-%H-%M-%S')}"
DEFAULT_MR_TARGET_BRANCH = os.getenv('MERGE_REQUEST_TARGET_BRANCH', 'main')
DEFAULT_MR_TITLE = os.getenv('MERGE_REQUEST_TITLE', 'Merge request from gitlab-ci')

RELEASE_BRANCH_PATTERN = re.compile("release/.*")


app = typer.Typer(
    no_args_is_help=True,
    help="""
        Helper tool for interacting with GitLab in CI.
    """,
    rich_markup_mode="rich"
)

# add HTTP retries to mitigate connection/communication issues
session = requests.Session()
session.mount(
    "https://",
    HTTPAdapter(
        max_retries=Retry(total=5, backoff_factor=1, status_forcelist=[502, 503, 504]),
    ),
)


def error(message: str) -> NoReturn:
    print(f"Error: {message}", file=sys.stderr)

    raise typer.Exit(code=1)

def check_for_changes(repo: Repo) -> bool:
    return repo.is_dirty(untracked_files=True)


def commit_and_push_changes(repo: Repo, branch_name: str, changes: Optional[list[str]]) -> None:
    author = Actor(USER_NAME, USER_EMAIL)

    if changes:
        for change in changes:
            repo.git.add(change)
    else:
        repo.git.add(A=True)
    repo.git.checkout("HEAD", b=branch_name)

    try:
        repo.index.commit("Automated commit by CI", author=author, committer=author)
    except git.exc.HookExecutionError as exc:
        error(str(exc))

    origin = repo.remote(name="origin")
    origin.push(branch_name)


def create_merge_request(title: str, branch: str, target_branch: str) -> None:
    url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
    headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}

    data = {
        "source_branch": branch,
        "target_branch": target_branch,
        "title": title,
    }

    response = requests.post(url, headers=headers, data=data)
    if response.status_code != 201:
        print(f"Failed to create merge request. Status: {response.status_code}, Response: {response.text}")
        raise typer.Exit(code=1)

    print(f"Merge request {response.json()['references']['full']} created successfully.")


@app.command("backport-to-release")
def backport_to_release(
    commit: str = typer.Option(
        default="",
        help="Commit to cherry-pick into the release branch"
    )
) -> None:
    """
    Cherry pick changes from the merged merge request associated with the commit.
    """

    repo = Repo('.')

    # Find release branch
    refs = sorted(list(filter(lambda r: RELEASE_BRANCH_PATTERN.match(r),
                              [ref.name.removeprefix("origin/") for ref in repo.remotes.origin.refs])), reverse=True)

    if not refs:
        error('could not find a release branch')

    release_branch = refs[0]
    print(f"Using target branch {release_branch}")

    response_mrs = requests.get(f"{GITLAB_API_URL}/projects/{PROJECT_ID}/repository/commits/{commit}/merge_requests",
                                headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    if response_mrs.status_code != 200:
        print(f"Failed to fetch merge requests associated with commit {commit}")
        return typer.Exit(code=1)

    # Find merged MRs staged to be backported
    merge_requests = [
        mr for mr in response_mrs.json()
        if mr["state"] == "merged" and "Reviewed" in mr["labels"] # "Backport to release" in mr["labels"]
    ]

    if not merge_requests:
        print("No (merged) merge requests associated with the commit and marked for backport found.")
        return typer.Exit()

    mr_iid = merge_requests[0]['iid']
    print(f"Using merge request !{str(mr_iid)}")

    # Get commits from the MR
    response_commits = requests.get(f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests/{str(mr_iid)}/commits",
                                headers={"PRIVATE-TOKEN": GITLAB_TOKEN})
    if response_commits.status_code != 200:
        print(f"Failed to fetch commits associated with the merge request !{str(mr_iid)}")
        return typer.Exit(code=1)

    commit_ids = [commit['id'] for commit in response_commits.json()]

    if not commit_ids:
        error("No commits for backport selected")

    print(f"Cherry-picking commits {' '.join(commit_ids)}")

    # Create MR branch and apply cherry-picks
    repo.remotes.origin.fetch(release_branch)
    mr_branch = f"backport-{str(mr_iid)}-{release_branch}"
    repo.git.checkout(f"origin/{release_branch}", B=mr_branch)

    try:
        repo.git.cherry_pick(*commit_ids)
    except git.GitCommandError as exc:
        error('cherry-picks failed to apply')

    repo.remotes.origin.push(mr_branch, "--force")

    create_merge_request(f"[Backport] !{str(mr_iid)}", mr_branch, release_branch)

    return typer.Exit()


@app.command("create-merge-request")
def create_merge_request(
    title: str = typer.Option(
        default=DEFAULT_MR_TITLE,
        help="Commit and merge request title"
    ),
    branch: str = typer.Option(
        default=DEFAULT_MR_BRANCH,
        help="Name of the commit branch."
    ),
    target_branch: str = typer.Option(
        default=DEFAULT_MR_TARGET_BRANCH,
        help="Name of the merge request target branch."
    ),
    changes: Optional[list[str]] = typer.Option(
        default=None,
        help="Path of the changes to commit, can be specified multiple times. By default all changes are added."
    )
) -> None:
    """
    Commit local changes to a new branch and create a merge request from them.

    By default all changes are commited, use `changes` option to submit different paths to commit.
    """
    repo = Repo('.')

    if not check_for_changes(repo):
        print("🙈No changes detected. Cowardly giving up creating an MR.")
        raise typer.Exit()

    print("Changes detected. Proceeding with commit and merge request creation...")
    commit_and_push_changes(repo, branch, changes)
    create_merge_request(title, branch, target_branch)

    return typer.Exit()


@app.callback()
def callback() -> None:
    if not GITLAB_TOKEN:
        error("No GitLab token set in environment variables CI_JOB_TOKEN or GITLAB_PRIVATE_TOKEN.")


def main() -> None:
    """
    Main entrypoint for the script.
    """
    app()
