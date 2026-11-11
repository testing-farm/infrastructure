#!/bin/bash
# Ensure every given secret file is ansible-vault encrypted.
# Only the file header is read — the content is never printed.

set -euo pipefail

rc=0

for f in "$@"; do
    if [ "$(head -c 15 "$f")" != '$ANSIBLE_VAULT;' ]; then
        echo "ERROR: $f is not ansible-vault encrypted"
        rc=1
    fi
done

exit "$rc"
