#!/usr/bin/env python3

"""
Derive the download URL of the qcow2 produced by a Testing Farm
/images/artifacts/qcow2 request.

Usage: qcow2-url.py <request-id-or-string-containing-it>

Prints the qcow2 URL to stdout (and nothing else there, so callers can capture
it directly); progress and diagnostics go to stderr.

The URL is built from the Testing Farm API alone: the request's artifacts URL
plus the tmt workdir of the qcow2 plan. The GitLab runner cannot reach the
Red Hat ranch artifact server, so the URL is not checked.

TESTING_FARM_API_URL selects the Testing Farm API (defaults to the public
endpoint, which holds every request regardless of ranch; the GET needs no
token). QCOW2_PLAN overrides the plan name (default: /images/artifacts/qcow2),
QCOW2_FILE the file name (default: artifacts-bootc.qcow2, matching qcow2.fmf).

Pure stdlib (no curl/jq), so it runs in minimal images such as the Testing
Farm cli image.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

API_URL = os.environ.get("TESTING_FARM_API_URL") or "https://api.dev.testing-farm.io/v0.1"
QCOW2_PLAN = os.environ.get("QCOW2_PLAN") or "/images/artifacts/qcow2"
QCOW2_FILE = os.environ.get("QCOW2_FILE") or "artifacts-bootc.qcow2"

UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
)


def info(msg):
    print("\033[0;34m[i] {}\033[0m".format(msg), file=sys.stderr)


def error(msg):
    print("\033[0;31m[E] {}\033[0m".format(msg), file=sys.stderr)
    sys.exit(1)


def main():
    match = UUID_RE.search(sys.argv[1] if len(sys.argv) > 1 else "")
    if not match:
        error("Valid request ID is required as the first parameter.")
    request_id = match.group(0)
    info("request id: {}".format(request_id))

    request_url = "{}/requests/{}".format(API_URL.rstrip("/"), request_id)
    info("GET {}".format(request_url))
    try:
        with urllib.request.urlopen(request_url, timeout=30) as resp:
            request = json.load(resp)
    except (urllib.error.URLError, ValueError) as exc:
        error("Could not query request '{}': {}".format(request_id, exc))

    run = request.get("run") or {}
    artifacts = run.get("artifacts")
    if not artifacts:
        error("Could not find artifacts URL for request '{}'.".format(request_id))
    info("artifacts base: {}".format(artifacts))

    # Every pipeline stage of a plan records the plan's tmt workdir.
    workdirs = {
        stage["workdir"]
        for stage in (run.get("stages") or {}).get("pipeline") or []
        if stage.get("plan") == QCOW2_PLAN and stage.get("workdir")
    }
    if len(workdirs) != 1:
        error(
            "Expected one workdir of plan '{}' in request '{}', found {}.".format(
                QCOW2_PLAN, request_id, sorted(workdirs) or "none"
            )
        )
    workdir = workdirs.pop()
    info("workdir: {}".format(workdir))

    print(
        "{}/{}/{}/data/{}".format(
            artifacts.rstrip("/"), workdir, QCOW2_PLAN.strip("/"), QCOW2_FILE
        )
    )


if __name__ == "__main__":
    main()
