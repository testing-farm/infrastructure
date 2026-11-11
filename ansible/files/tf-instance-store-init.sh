#!/bin/bash
# Rebuild `/data` on the NVMe instance store after the instance was stopped and started.
#
# A stop/start wipes the instance store. On a normal reboot the store is intact and this does nothing.
set -euo pipefail

DEVICE="${TF_INSTANCE_STORE_DEVICE:-/dev/nvme0n1}"
PARTITION="${DEVICE}p1"
MOUNT_PATH=/data
SWAPFILE="$MOUNT_PATH/swapfile"
SWAP_SIZE=16G
SECRETS_LIST=/etc/testing-farm/podman-secrets
SECRETS_DIR=/etc/citool.d/config

if mountpoint -q "$MOUNT_PATH"; then
  echo "$MOUNT_PATH is mounted, nothing to do"
  exit 0
fi

if [ -b "$PARTITION" ] && blkid "$PARTITION" >/dev/null 2>&1; then
  # filesystem is intact, the mount was just not done, e.g. a slow device
  mount "$MOUNT_PATH"
  exit 0
fi

echo "Instance store $DEVICE is empty, rebuilding $MOUNT_PATH"

if [ ! -b "$PARTITION" ]; then
  parted --script "$DEVICE" mklabel gpt mkpart primary ext4 0% 100%
  udevadm settle
  for _ in $(seq 1 30); do [ -b "$PARTITION" ] && break; sleep 1; done
fi

mkfs.ext4 -F -E nodiscard,lazy_itable_init=1 "$PARTITION"

mkdir -p "$MOUNT_PATH"
mount "$PARTITION" "$MOUNT_PATH"
chmod 0755 "$MOUNT_PATH"

mkdir -p "$MOUNT_PATH/nomad" "$MOUNT_PATH/containers"
chmod 0700 "$MOUNT_PATH/containers"
restorecon -RF "$MOUNT_PATH" || true

fallocate -l "$SWAP_SIZE" "$SWAPFILE"
chmod 0600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"

# Podman secrets live in the main store, recreate them from the files rendered by Ansible.
if [ -f "$SECRETS_LIST" ]; then
  while read -r name; do
    [ -n "$name" ] || continue
    podman secret rm "$name" 2>/dev/null || true
    podman secret create "$name" "$SECRETS_DIR/$name" >/dev/null
  done <"$SECRETS_LIST"
fi

echo "$MOUNT_PATH rebuilt"
