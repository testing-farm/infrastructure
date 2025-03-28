#!/usr/bin/env python

#
# Implements utility functions for GitLab.
#

import os
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
GITLAB_TOKEN = os.getenv('CI_JOB_TOKEN') or os.getenv('GITLAB_PRIVATE_TOKEN')

GITLAB_API_URL = f"https://{GITLAB_DOMAIN}/api/v4"

USER_NAME = 'Testing Farm Bot'
USER_EMAIL = 'tft@redhat.com'

DEFAULT_MR_BRANCH = f"gitlab-ci-{datetime.now().strftime('%Y-%m-%d-%H-%M-%S')}"
DEFAULT_MR_TARGET_BRANCH = os.getenv('MERGE_REQUEST_TARGET_BRANCH', 'main')
DEFAULT_MR_TITLE = os.getenv('MERGE_REQUEST_TITLE', 'Merge request from gitlab-ci')


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

    url = f"{GITLAB_API_URL}/projects/{PROJECT_ID}/merge_requests"
    headers = {"PRIVATE-TOKEN": GITLAB_TOKEN}

    data = {
        "source_branch": branch,
        "target_branch": target_branch,
        "title": title,
    }

    response = requests.post(url, headers=headers, data=data)
    if response.status_code == 201:
        print("Merge request created successfully.")
        raise typer.Exit()

    print(f"Failed to create merge request. Status: {response.status_code}, Response: {response.text}")
    raise typer.Exit(code=1)


@app.callback()
def callback() -> None:
    if not GITLAB_TOKEN:
        error("No GitLab token set in environment variables CI_JOB_TOKEN or GITLAB_PRIVATE_TOKEN.")


def main() -> None:
    """
    Main entrypoint for the script.
    """
    app()
