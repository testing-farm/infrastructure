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

# IMAGE_NAME must be unique per upload: tft-admin's cloud compose sync/import are
# keyed on it and silently no-op when the name already exists, so reusing a name
# would keep a stale image. Callers pass a unique name (commit sha on the default
# branch, pipeline id on MRs) and REMOVE_AFTER_TEST=1 to clean up throwaway MR
# uploads. REMOVE_AFTER_TEST is honoured by the upstream run.sh below.

# Reuse the upstream upload orchestration (tft-admin sync + cross-region import +
# artemis cache update). Fetch it fresh so we stay in sync with testing-farm/tests.
tests_url="${TESTS_URL:-https://gitlab.com/testing-farm/tests.git}"
tests_ref="${TESTS_REF:-main}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
git clone --quiet --depth 1 --branch "$tests_ref" "$tests_url" "$workdir/tests"
# run.sh relies on its own `#!/bin/bash -e`; invoking it with `bash` drops that
# shebang and our set -e does not carry into the new interpreter, so pass -e
# explicitly or a failed sync/import/cache-update would exit 0 (false success).
exec bash -e "$workdir/tests/testing-farm/upload-qcow2/run.sh"
