#!/bin/bash
# Validate all ansible-vault encrypted JSON files under ansible/secrets/
# Decrypted content is never printed — only passed to jq for syntax validation.

set -euo pipefail

SECRETS_DIR="${1:-ansible/secrets}"
rc=0

for f in $(find "$SECRETS_DIR" -name '*.json'); do
    echo "Validating $f ..."
    if ! ansible-vault view "$f" | jq empty; then
        echo "ERROR: $f is not valid JSON"
        rc=1
    fi
done

exit "$rc"
