#!/bin/bash

set -euo pipefail

#
# Publish goss binaries and the dgoss wrapper to the public `testing-farm-public`
# bucket, so that guests and CI can download them from
# `https://testing-farm-public.s3.amazonaws.com/goss/<version>/goss-linux-<arch>`
# and `.../goss/<version>/dgoss` instead of the flaky GitHub release downloads.
#
# Requires working AWS credentials allowed to `s3:PutObject` under the `goss/`
# prefix - the CI job assumes the testing-farm-goss-publisher role through the
# `gitlab.com` OIDC provider. The bucket has versioning enabled, to roll back
# copy a previous version over the current one. All downloads are verified
# against the checksums published for the release.
#
# The image (public.ecr.aws/aws-cli/aws-cli:2...) has no tar command and thus
# python's tarfile module is used to decompress the archive.

: "${GOSS_VERSION:?Set GOSS_VERSION (e.g. v0.4.10) when running this job}"

# GitLab CI injects the OIDC token as AWS_ID_TOKEN - write it to the file the
# AWS CLI expects, so it assumes the role via web identity. Outside CI, with
# regular credentials, this is skipped.
if [ -n "${AWS_ID_TOKEN:-}" ]; then
    export AWS_WEB_IDENTITY_TOKEN_FILE="${AWS_WEB_IDENTITY_TOKEN_FILE:-/tmp/web-identity-token}"
    printf '%s' "$AWS_ID_TOKEN" > "$AWS_WEB_IDENTITY_TOKEN_FILE"
fi

SUMS="goss_${GOSS_VERSION#v}_SHA256SUMS"
echo "Fetching checksums..."
curl -fsSL "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/${SUMS}" -o "${SUMS}"

for ARCH in x86_64 aarch64 s390x ppc64le; do
    # goss uses arm64 rather than aarch64. The rest match from 0.4.10.
    UPSTREAM_ARCH="$ARCH"
    if [ "$ARCH" = aarch64 ]; then UPSTREAM_ARCH=arm64; fi

    ARCHIVE="goss_${GOSS_VERSION#v}_linux_${UPSTREAM_ARCH}.tar.gz"

    echo "Fetching goss ${GOSS_VERSION} for ${ARCH}..."
    curl -fsSL "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/${ARCHIVE}" -o "${ARCHIVE}"

    # goss publishes the checksums all in one file. So we find the right line to verify:
    grep " ${ARCHIVE}$" "${SUMS}" | sha256sum -c -

    # the aws-cli image ships no tar, extract via python's tarfile instead
    python3 -c "import tarfile; tarfile.open('${ARCHIVE}').extract('goss')"

    aws s3 cp --no-progress goss "s3://testing-farm-public/goss/${GOSS_VERSION}/goss-linux-${ARCH}"
done

echo "Fetching dgoss ${GOSS_VERSION}..."
curl -fsSL "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/dgoss" -o dgoss
curl -fsSL "https://github.com/goss-org/goss/releases/download/${GOSS_VERSION}/dgoss.sha256" -o dgoss.sha256
sha256sum -c dgoss.sha256
aws s3 cp --no-progress dgoss "s3://testing-farm-public/goss/${GOSS_VERSION}/dgoss"

echo "Published goss ${GOSS_VERSION} for x86_64, aarch64, s390x and ppc64le, and dgoss"
