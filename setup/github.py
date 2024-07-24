#!/usr/bin/env python

#
# Implements utility functions for GitHub.
#

import os
import sys
import subprocess
from functools import lru_cache
from typing import Any, Dict, List, Optional, NoReturn

import requests
import typer
from requests.adapters import HTTPAdapter
from ruamel.yaml import YAML
from urllib3 import Retry


GITHUB_API_URL="https://api.github.com"
SECRETS_FILE_VARNAME="SECRETS_FILE"  # pragma: allowlist secret

app = typer.Typer(
    no_args_is_help=True,
    help=f"""
Tool for interacting with GitHub API.
""",
    rich_markup_mode="rich"
)

# add HTTP retries to mitigate connection/communication issues
session = requests.Session()
session.mount(
    "https://",
    HTTPAdapter(
        max_retries=Retry(total=5, backoff_factor=0.1, status_forcelist=[502, 503, 504]),
    ),
)


def error(message: str, details: Optional[Any] = None) -> NoReturn:
    print(f"Error: {message}", file=sys.stderr)

    if details:
        print(f"Details: {details}")

    raise typer.Exit(code=1)


def warn(message: str) -> None:
    print(f"Warning: {message}", file=sys.stderr)


def get_error_detail(response: requests.Response) -> Any:
    return response.json()["errors"][0].get("detail") or response.json()["errors"][0].get("title")


def request(
    endpoint: str,
    headers: Optional[Dict[Any, Any]] = None,
    params: Optional[Dict[Any, Any]] = None,
    status_codes: Optional[List[int]] = None,
    method: str = "get",
    error_response: bool = False,
    **kwargs: Any,
) -> Any:
    """
    Requests method wrapper.
    """
    status_codes = status_codes or [200, 201]

    response = getattr(session, method)(f"{GITHUB_API_URL}/{endpoint}", headers=headers, params=params, **kwargs)

    if response.status_code >= 400 and response.status_code < 500:
        if error_response:
            return response

        error(get_error_detail(response))

    elif response.status_code >= 500:
        response.raise_for_status()

    return response


@lru_cache(maxsize=None)
def get_credentials() -> Dict[Any,Any]:
    # Read the vault password, environment variable presence is checked by the tool at start
    filename = os.getenv(SECRETS_FILE_VARNAME, "none")
    output = subprocess.check_output(["ansible-vault", "view", filename])
    return YAML(typ='safe').load(output)


def get_nested_value(data: Dict[str, Any], *keys: str) -> Optional[str]:
    for key in keys:
        if not isinstance(data, dict) or not data:
            return None
        data = data.get(key, {})
    return data if isinstance(data, str) else None


def get_registration_token(owner: str, repository: str) -> str:
    keys = [
        "credentials",
        "github",
        owner.replace("-", "_"),
        "runners",
        repository.replace("-", "_"),
        "registration_token"
    ]
    token = get_nested_value(get_credentials(), *keys)

    if not token:
        error(f'Retrieval token not found under {".".join(keys)}')

    return token


@app.command("worker-registration-token")
def cmd_worker_registration_token(owner: str, repository: str) -> None:
    """
    Retrieve worker registration token for given GitHub repository, specified by owner and repository name.

    The token for retrieval is looked up from Ansible Vault credentials file specified by SECRETS_FILE environment variable.

    It is expected to be found under [underline]credentials.github.<OWNER>.runners.<REPOSITORY>.registration_token[/underline] in the credentials file.

    Note that the hyphen '-' characters are replaced by underscores '_' in [underline]OWNER[/underline] and [underline]REPOSITORY[/underline] strings.

    For details of the required permissions of the token retrieval see [link= https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository]GitHub docs[/link].
    """

    registration_token = get_registration_token(owner, repository)

    response = request(
        f"repos/{owner}/{repository}/actions/runners/registration-token",
        method="post",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {registration_token}",
            "X-GitHub-Api-Version": "2022-11-28"
        },
        error_response=True
    )

    if not response:
        error(
            f"Failed to retrieve worker registration token for 'https://github.com/{owner}/{repository}'",
            response.json()
        )

    print(response.json()["token"])


@app.callback()
def callback() -> None:
    if not os.getenv(SECRETS_FILE_VARNAME):
        error(f"No {SECRETS_FILE_VARNAME} environment variable, please setup correctly the infrastructure repository!")


def main() -> None:
    """
    Main entrypoint for the script.
    """
    app()
