#!/bin/bash
# Upload the artifact-server qcow2 to a Testing Farm cloud as an AMI, using
# tft-admin (shipped in the cnc image, quay.io/testing-farm/cnc).
#
# The container image and the qcow2 are built on Testing Farm via the tmt plans
# in this directory (container.fmf, qcow2.fmf) - see README.adoc. This script
# performs the one step those build tests do not cover: importing the built
# qcow2 into an AMI and uploading it to AWS for the deploy (TFT-4797), which
# consumes it as ARTIFACTS_SERVER_AMI. It mirrors testing-farm/tests
# /testing-farm/upload-qcow2 (TFT-4492), but runs directly in a cnc job.
#
# Env (required):
#   QCOW2_URL        URL of the qcow2 to upload, from the qcow2 build request
#                    artifacts.
#   VAULT_SECRET_ID  Hashicorp Vault secret id; the cnc entrypoint uses it to
#                    fetch the cloud credentials.
#
# Env (optional):
#   CLOUD       target Testing Farm cloud            (default arr-aws)
#   IMAGE_NAME  cloud compose / AMI name             (default artifacts-bootc-<arch>)
#   QCOW2_ARCH  image architecture                   (default x86_64)
set -euo pipefail

CLOUD="${CLOUD:-arr-aws}"
QCOW2_ARCH="${QCOW2_ARCH:-x86_64}"
IMAGE_NAME="${IMAGE_NAME:-artifacts-bootc-$QCOW2_ARCH}"

if [ -z "${QCOW2_URL:-}" ]; then
    echo "Error: QCOW2_URL must be set to the qcow2 to upload (from the qcow2 build artifacts)." >&2
    exit 1
fi

# In the cnc image /entrypoint.sh materialises the cloud credentials from Vault
# (VAULT_SECRET_ID). Skip it when running outside cnc with tft-admin already set up.
if [ -x /entrypoint.sh ]; then
    echo "🔧 cnc entrypoint: fetching cloud credentials from Vault"
    /entrypoint.sh
fi

echo "☁️  selecting cloud $CLOUD"
tft-admin cloud set "$CLOUD"

echo "⬆️  syncing $IMAGE_NAME ($QCOW2_ARCH) from $QCOW2_URL"
tft-admin cloud compose sync --cloud-compose "$IMAGE_NAME" --from-url "$QCOW2_URL" --arch "$QCOW2_ARCH"

# On AWS the AMI is created in us-east-1; copy it to us-east-2 as well.
if [ "$CLOUD" = "arr-aws" ]; then
    echo "🌎 copying $IMAGE_NAME from us-east-1 to us-east-2"
    tft-admin cloud compose import --compose "$IMAGE_NAME" --source-region us-east-1 --target-regions us-east-2
fi

echo "✅ done: $IMAGE_NAME uploaded to $CLOUD"
echo "   Pass the resulting AMI to TFT-4797 as ARTIFACTS_SERVER_AMI (consumed by"
echo "   terragrunt/environments/production/artifacts-redhat/ec2/terragrunt.hcl)."
