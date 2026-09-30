#!/bin/bash -eu

#
# Derive the download URL of the qcow2 produced by a Testing Farm
# /images/bootc-artifacts/qcow2 build request.
#
# Usage: qcow2-url.sh <request-id-or-string-containing-it>
#
# Prints the qcow2 URL to stdout (and nothing else there, so callers can capture
# it directly). Needs TESTING_FARM_API_URL in the environment. QCOW2_FILE may be
# overridden (default: artifacts-bootc.qcow2, matching qcow2.fmf).
#

set -o pipefail

error() {
    echo -e "\033[0;31m[E] $*\033[0m" >&2
    exit 1
}

QCOW2_FILE="${QCOW2_FILE:-artifacts-bootc.qcow2}"

REQUEST_ID=$(sed -nE 's/.*([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}).*/\1/p' <<< "${1:-}")

[ -z "$REQUEST_ID" ] && error "Valid request ID is required as the first parameter."
[ -z "${TESTING_FARM_API_URL:-}" ] && error "TESTING_FARM_API_URL not set in the environment."

ARTIFACTS_BASE=$(curl -sf "${TESTING_FARM_API_URL}/requests/${REQUEST_ID}" | jq -r '.run.artifacts')
[ -z "$ARTIFACTS_BASE" ] || [ "$ARTIFACTS_BASE" == "null" ] \
    && error "Could not find artifacts URL for request '${REQUEST_ID}'."

# The plan-data directory holding the qcow2 is the 'data' log in results.xml.
PLAN_DATA_URL=$(curl -sf "${ARTIFACTS_BASE%/}/results.xml" \
    | sed -nE 's/.*<log[^>]*name="data"[^>]*href="([^"]+)".*/\1/p' \
    | head -n1)
[ -z "$PLAN_DATA_URL" ] && error "Could not find the plan data URL in results.xml for request '${REQUEST_ID}'."

QCOW2_URL="${PLAN_DATA_URL%/}/${QCOW2_FILE}"

curl -sfI "$QCOW2_URL" >/dev/null || error "qcow2 not reachable at '${QCOW2_URL}'."

echo "$QCOW2_URL"
