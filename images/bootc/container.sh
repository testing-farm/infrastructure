#!/bin/bash
set -euxo pipefail

if [ -z "$OS" ]; then
  echo "Error: OS not specified, use 'fedora' or 'centos'"
  exit 1
fi

if [ -z "$VERSION" ]; then
  echo "Error: VERSION not specified, use 41, 42, etc for fedora; stream9, stream10, etc for centos'"
  exit 1
fi

if [ "$OS" = "fedora" ]; then
  BASE_IMAGE=quay.io/fedora/fedora-bootc:${VERSION,,}
  TARGET_IMAGE=quay.io/testing-farm/fedora-bootc:${VERSION,,}
elif [ "$OS" = "centos" ]; then
  BASE_IMAGE=quay.io/centos-bootc/centos-bootc:stream$VERSION
  TARGET_IMAGE=quay.io/testing-farm/centos-bootc:stream$VERSION

  if ! [[ "$VERSION" =~ (9|10) ]]; then
    echo "Error: VERSION does for centos stream is invalid, must be 9 or 10"
    exit 1
  fi
else
  echo "Error: Invalid OS, use 'fedora' or 'centos'"
  exit 1
fi

podman manifest rm $TARGET_IMAGE || true
podman rmi -f $TARGET_IMAGE || true
podman manifest create $TARGET_IMAGE

podman build --no-cache --platform linux/arm64 --pull=always --network=host --build-arg ARCH=aarch64 --build-arg BASE_IMAGE=$BASE_IMAGE --manifest $TARGET_IMAGE .
podman build --no-cache --platform linux/amd64 --pull=always --network=host --build-arg ARCH=x86_64 --build-arg BASE_IMAGE=$BASE_IMAGE --manifest $TARGET_IMAGE .

podman manifest push $TARGET_IMAGE
