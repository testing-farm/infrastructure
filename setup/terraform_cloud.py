#!/usr/bin/env python

#
# Implements Terraform Cloud workspace operations needed for the infrastructure.
#
# For documentation see https://developer.hashicorp.com/terraform/cloud-docs/api-docs/workspaces.
#
# Note that the script needs organization level token, which is different from the token used for the cloud backend.
#

import itertools
import os
import sys
from typing import Any, List, Optional

import requests
import typer
from requests.adapters import HTTPAdapter
from urllib3 import Retry

TFCLOUD_VARIABLE_NAME = "TF_TOKEN_app_terraform_io"
TFCLOUD_API_URL = f"{os.getenv('TF_VAR_terraform_api_url')}/organizations/testing-farm"
HEADERS = {
    "Authorization": f"Bearer {os.getenv(TFCLOUD_VARIABLE_NAME)}",
    "Content-Type": "application/vnd.api+json",
}

app = typer.Typer(
    no_args_is_help=True,
    help=f"""
Tool for interaction with Terraform Cloud API.
See https://developer.hashicorp.com/terraform/cloud-docs/api-docs for details.

Requires Terraform Cloud Token exported in variable `{TFCLOUD_VARIABLE_NAME}`.
""",
)

# add HTTP retries to mitigate connection/communication issues
session = requests.Session()
session.mount(
    "https://",
    HTTPAdapter(
        max_retries=Retry(total=5, backoff_factor=0.1, status_forcelist=[502, 503, 504]),
    ),
)


def error(message: str, details: Optional[Any] = None) -> None:
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
    status_codes: Optional[List[int]] = None,
    method: str = "get",
    error_response: bool = False,
    **kwargs: Any,
) -> Any:
    """
    Requests method wrapper.
    """
    status_codes = status_codes or [200, 201]

    response = getattr(session, method)(f"{TFCLOUD_API_URL}/{endpoint}", headers=HEADERS, **kwargs)

    if response.status_code >= 400 and response.status_code < 500:
        if error_response:
            return response

        error(get_error_detail(response))

    elif response.status_code >= 500:
        response.raise_for_status()

    return response


def list_workspaces() -> List[Any]:
    endpoint = "workspaces"
    responses = [request(endpoint).json()]

    while responses[-1]["links"]["next"]:
        responses.append(request(endpoint).json())

    return list(itertools.chain([workspace for response in responses for workspace in response["data"]]))


@app.command("create-workspace")
def cmd_create_workspace(name: str, ignore_existing: bool = False) -> None:
    """
    Create workspace with given NAME.
    """

    response = request(
        "workspaces",
        method="post",
        error_response=True,
        json={
            "data": {
                "type": "workspaces",
                "attributes": {
                    "name": name,
                    "execution-mode": "local",
                    "setting-overwrites": {
                        "execution-mode": True,
                    },
                },
            },
        },
    )

    if response.status_code == 422:
        if ignore_existing:
            raise typer.Exit
        error(f"Workspace '{name}' already exists!")

    if not response:
        error(f"Failed to create workspace '{name}'", response.json())

    print(f"Workspace '{name}' created.")


@app.command("list-workspaces")
def cmd_list_workspaces() -> None:
    """
    List available workspaces.
    """
    workspaces = list_workspaces()

    if not workspaces:
        error("No workspaces found")
        return

    print("\n".join(workspace["attributes"]["name"] for workspace in workspaces))


@app.command("delete-workspace")
def cmd_delete_workspace(name: str, confirm: bool = False, production_confirm: bool = False) -> None:
    """
    Delete a workspace. Requires `--confirm` to really delete it.
    """

    if confirm:
        if 'production' in name and not production_confirm:
            warn(f"Would remove production workspace '{name}'. Run with '--production-confirm' to really remove the item.")
            return

        request(f"workspaces/{name}", method="delete")
        print(f"Removed workspace '{name}'")
        return

    warn(f"Would remove workspace '{name}'. Run with '--confirm' to really remove the item.")


@app.callback()
def callback() -> None:
    if not os.getenv(TFCLOUD_VARIABLE_NAME):
        error(f"No {TFCLOUD_VARIABLE_NAME} environment variable, please setup correctly the infrastructure repository!")


def main() -> None:
    """
    Main entrypoint for the script.
    """
    app()
