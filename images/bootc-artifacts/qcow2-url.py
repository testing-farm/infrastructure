#!/usr/bin/env python3

"""
Derive the download URL of the qcow2 produced by a Testing Farm
/images/bootc-artifacts/qcow2 build request.

Usage: qcow2-url.py <request-id-or-string-containing-it>

Prints the qcow2 URL to stdout (and nothing else there, so callers can capture
it directly). TESTING_FARM_API_URL selects the Testing Farm API (defaults to the
public endpoint, which holds every request regardless of ranch; the GET needs no
token). QCOW2_FILE overrides the file name (default: artifacts-bootc.qcow2,
matching qcow2.fmf).

Pure stdlib (no curl/jq): the Testing Farm cli image is Alpine with python3 but
no curl/jq.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request
from urllib.parse import urljoin

API_URL = os.environ.get("TESTING_FARM_API_URL") or "https://api.dev.testing-farm.io/v0.1"
QCOW2_FILE = os.environ.get("QCOW2_FILE") or "artifacts-bootc.qcow2"

UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"
)


def error(msg):
    print("\033[0;31m[E] {}\033[0m".format(msg), file=sys.stderr)
    sys.exit(1)


def http(url, method="GET"):
    req = urllib.request.Request(url, method=method)
    return urllib.request.urlopen(req, timeout=30)


def main():
    match = UUID_RE.search(sys.argv[1] if len(sys.argv) > 1 else "")
    if not match:
        error("Valid request ID is required as the first parameter.")
    request_id = match.group(0)

    try:
        with http("{}/requests/{}".format(API_URL.rstrip("/"), request_id)) as resp:
            request = json.load(resp)
    except (urllib.error.URLError, ValueError) as exc:
        error("Could not query request '{}': {}".format(request_id, exc))

    artifacts = (request.get("run") or {}).get("artifacts")
    if not artifacts:
        error("Could not find artifacts URL for request '{}'.".format(request_id))

    results_url = "{}/results.xml".format(artifacts.rstrip("/"))
    try:
        with http(results_url) as resp:
            results = resp.read().decode("utf-8", "replace")
    except urllib.error.URLError as exc:
        error("Could not fetch results.xml from '{}': {}".format(artifacts, exc))

    # The plan-data directory holding the qcow2 is the 'data' log in results.xml.
    plan_data_url = None
    for log in re.findall(r"<log\b[^>]*>", results):
        if 'name="data"' in log:
            href = re.search(r'href="([^"]+)"', log)
            if href:
                plan_data_url = urljoin(results_url, href.group(1))
                break
    if not plan_data_url:
        error(
            "Could not find the plan data URL in results.xml for request '{}'.".format(
                request_id
            )
        )

    qcow2_url = "{}/{}".format(plan_data_url.rstrip("/"), QCOW2_FILE)

    try:
        http(qcow2_url, method="HEAD")
    except urllib.error.URLError as exc:
        error("qcow2 not reachable at '{}': {}".format(qcow2_url, exc))

    print(qcow2_url)


if __name__ == "__main__":
    main()
