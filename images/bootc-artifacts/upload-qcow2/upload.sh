#!/bin/bash
#
# Derive the qcow2 download URL from a /images/bootc-artifacts/qcow2 build request
# and upload it to the cloud by reusing the testing-farm/tests upload-qcow2 run.sh.
#
# Derivation and upload run in this one script because the cnc container runs as a
# non-root user that cannot write tmt's work directory, so QCOW2_URL cannot be passed
# between tmt steps. Run inside Testing Farm (cnc image), which can reach the Red Hat
# ranch artifact server. See ../upload.fmf and ../README.adoc.

set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

error() { echo "[E] $*" >&2; exit 1; }

# Derive QCOW2_URL from the build request, unless a ready URL was supplied.
if [ -z "${QCOW2_URL:-}" ]; then
    [ -n "${QCOW2_REQUEST:-}" ] || error "QCOW2_REQUEST or QCOW2_URL must be set"
    QCOW2_URL="$(python3 "$here/../qcow2-url.py" "$QCOW2_REQUEST")"
    export QCOW2_URL
fi
echo "[i] QCOW2_URL=$QCOW2_URL"

# Optionally force a fresh upload. tft-admin's cloud compose sync/import are keyed on
# IMAGE_NAME and no-op when the cloud image already exists, so delete it first. Best
# effort: tft-admin cloud compose delete only removes it in the source region
# (us-east-1); the us-east-2 copy is not removed yet (TFT-4650).
if [ -n "${FORCE_UPLOAD:-}" ]; then
    : "${CLOUD:?CLOUD must be set for FORCE_UPLOAD}"
    : "${IMAGE_NAME:?IMAGE_NAME must be set for FORCE_UPLOAD}"
    echo "[i] FORCE_UPLOAD set; deleting any existing $IMAGE_NAME from $CLOUD first"
    /entrypoint.sh
    tft-admin cloud set "$CLOUD"
    tft-admin cloud compose delete "$IMAGE_NAME" || echo "[i] nothing to delete (or delete failed); continuing"
fi

# Reuse the upstream upload orchestration (tft-admin sync + cross-region import +
# artemis cache update). Fetch it fresh so we stay in sync with testing-farm/tests.
tests_url="${TESTS_URL:-https://gitlab.com/testing-farm/tests.git}"
tests_ref="${TESTS_REF:-main}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
git clone --quiet --depth 1 --branch "$tests_ref" "$tests_url" "$workdir/tests"
exec bash "$workdir/tests/testing-farm/upload-qcow2/run.sh"
