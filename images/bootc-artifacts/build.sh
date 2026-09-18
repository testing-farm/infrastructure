#!/bin/bash
# Build the RHEL 10 bootc artifact-server image and (optionally) an AMI.
# TFT-4795. Runs locally via podman + bootc-image-builder.
#
# Usage:
#   ./build.sh image           Build and tag the bootc container image
#   ./build.sh ami             Build image, then produce an AMI (needs AWS creds)
#
# Env:
#   BASE_IMAGE   base bootc image     (default images.paas.redhat.com/testingfarm/rhel-bootc:10)
#   TARGET_IMAGE built image tag      (default quay.io/testing-farm/artifacts-bootc:latest)
#   AWS_REGION   AMI region           (default us-east-1)
#   AWS_BUCKET   S3 bucket for the AMI import staging
#
# Prereqs:
#   - `podman login images.paas.redhat.com` (base image is entitled)
#   - for `ami`: AWS credentials with EC2/S3 import permissions, and
#     `AWS_BUCKET` set to a writable bucket in `AWS_REGION`.
set -euo pipefail

cd "$(dirname "$0")"

BASE_IMAGE="${BASE_IMAGE:-images.paas.redhat.com/testingfarm/rhel-bootc:10}"
TARGET_IMAGE="${TARGET_IMAGE:-quay.io/testing-farm/artifacts-bootc:latest}"
AWS_REGION="${AWS_REGION:-us-east-1}"
BIB_IMAGE="registry.redhat.io/rhel10/bootc-image-builder:latest"

build_image() {
    echo "🔨 building $TARGET_IMAGE from $BASE_IMAGE"
    podman build \
        --pull=always \
        --build-arg BASE_IMAGE="$BASE_IMAGE" \
        -t "$TARGET_IMAGE" \
        .
}

build_ami() {
    build_image

    if [ -z "${AWS_BUCKET:-}" ]; then
        echo "Error: AWS_BUCKET must be set to build an AMI" >&2
        exit 1
    fi

    local aws_mounts=()
    [ -f "${AWS_CONFIG_FILE:-$HOME/.aws/config}" ] && aws_mounts+=(-v "${AWS_CONFIG_FILE:-$HOME/.aws/config}:/root/.aws/config:ro")
    [ -f "${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}" ] && aws_mounts+=(-v "${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}:/root/.aws/credentials:ro")

    echo "💿 building AMI in $AWS_REGION via bootc-image-builder"
    podman run \
        --rm -it --privileged \
        --pull=newer \
        --security-opt label=type:unconfined_t \
        "${aws_mounts[@]}" \
        --env AWS_PROFILE \
        "$BIB_IMAGE" \
        --type ami \
        --aws-region "$AWS_REGION" \
        --aws-bucket "$AWS_BUCKET" \
        --aws-ami-name "artifacts-bootc-$(date +%Y%m%d-%H%M%S)" \
        "$TARGET_IMAGE"

    echo "✅ AMI build finished. Pass the resulting AMI id to TFT-4797 as ARTIFACTS_SERVER_AMI."
}

case "${1:-image}" in
    image) build_image ;;
    ami)   build_ami ;;
    *)     echo "Usage: $0 {image|ami}" >&2; exit 1 ;;
esac
