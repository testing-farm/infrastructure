#!/bin/bash

if [ "$DEBUG" != "" ]; then
  set -x
fi

if [ "$USER" != "root" ]; then
    echo "This script has to be run as root!"
    exit 1
fi

CITOOL_IMAGE="${CITOOL_IMAGE:-citool:latest}"
CITOOL_CONFIG_DIR="${CITOOL_CONFIG_DIR:-/etc/citool.d}"
CITOOL_RUN_DIR="${CITOOL_RUN_DIR:-$PWD}"

echo "Known images:"
podman images

echo
image_id=`podman inspect -f '{{.Id}}' $CITOOL_IMAGE`
ctime=`podman inspect -f '{{.Created}}' $CITOOL_IMAGE`
echo "Image is $image_id, created on $ctime"

echo

# export image details into environmnet, so it gets to Sentry
export CITOOL_IMAGE
export CITOOL_IMAGE_ID="$image_id"
export CITOOL_IMAGE_CTIME="$ctime"

# --init is required to collect zombies processes
# --rm is required to cleanup the container after it has been run
# --privileged is required to run container based workloads
#
# /CONFIG and /ARTIFACTS are the default mounts of the upstream citoool container
podman run --init \
           --rm \
           --privileged \
           --name ${REQUEST_ID:-no-request-$RANDOM} \
           -v ${CITOOL_CONFIG_DIR}:/CONFIG:Z \
           -v ${CITOOL_RUN_DIR}:/var/ARTIFACTS:Z \
           ${CITOOL_EXTRA_PODMAN_ARGS} \
           "$CITOOL_IMAGE" "$@"
