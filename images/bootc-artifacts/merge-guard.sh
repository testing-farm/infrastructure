#!/bin/bash
# Fail while a MERGE-BLOCKER marker is present in .gitlab-ci.yml, so temporary
# measures cannot reach main unnoticed. Currently guards the "keep MR AMIs" change
# (REMOVE_AFTER_TEST disabled on MRs) in the image/artifacts-bootc/ami job. TFT-4795.
set -euo pipefail

marker='MERGE-BLOCKER'
if grep -nF "$marker" .gitlab-ci.yml; then
    echo "[E] $marker present (see above) - resolve the temporary change(s) before merge." >&2
    exit 1
fi
echo "[i] no $marker markers; nothing blocking merge."
