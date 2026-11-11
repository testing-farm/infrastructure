#!/bin/bash
# Remove unused images from the read-only podman image store on the root disk.
#
# The store is not touched by `podman system prune`, and it does not know about containers of the main store.
# Removing a layer used by a container would break it, so images used by any container are kept.
# An image pulled to the main store can reuse layers of this store, images sharing a layer with it are kept too.
#
# Usage: podman-ro-store-cleanup.sh [CURRENT_IMAGE]
#   CURRENT_IMAGE defaults to the content of /etc/testing-farm/citool-image
set -euo pipefail

RO_STORE="${PODMAN_RO_STORE:-/var/lib/containers/storage}"
# the store needs its own runroot, the default one belongs to the main store
RO_RUNROOT="${PODMAN_RO_RUNROOT:-/run/containers/storage-ro}"
current_image="${1:-$(cat /etc/testing-farm/citool-image 2>/dev/null || true)}"

ro_podman() {
  podman --root "$RO_STORE" --runroot "$RO_RUNROOT" --storage-opt '' "$@"
}

# images used by containers of the main store and of the read-only store
in_use="$( (podman ps -a --format '{{.ImageID}}'; ro_podman ps -a --format '{{.ImageID}}') | sort -u)"

is_in_use() {
  # `ps` prints the short ID, compare by prefix
  local id="$1" used
  while read -r used; do
    [ -n "$used" ] && [[ "$id" == "$used"* ]] && return 0
  done <<<"$in_use"
  return 1
}

# layers of the images in the main store, by uncompressed digest
main_layers="$(podman images --format '{{.ID}} {{.ReadOnly}}' | awk '$2 == "false" {print $1}' | sort -u \
  | xargs -r podman image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' | sort -u)"

shares_layer() {
  local layers
  [ -n "$main_layers" ] || return 1
  # not piped to `grep -q`, its early exit fails the pipeline under `pipefail`
  layers="$(ro_podman image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$1")" || return 1
  grep -xF -f <(printf '%s\n' "$main_layers") <<<"$layers" >/dev/null
}

# images to keep: `citool:latest` and the current image
keep=""
for ref in citool:latest ${current_image:+"$current_image"}; do
  id="$(ro_podman image inspect --format '{{.Id}}' "$ref" 2>/dev/null || true)"
  [ -n "$id" ] && keep="$keep ${id:0:12}"
done

ro_podman images --all --format '{{.ID}}' | sort -u | while read -r short; do
  [[ " $keep " == *" $short "* ]] && continue
  if is_in_use "$short"; then
    echo "keeping $short, used by a container"
    continue
  fi
  if shares_layer "$short"; then
    echo "keeping $short, shares a layer with an image of the main store"
    continue
  fi
  echo "removing $short"
  ro_podman rmi "$short" || echo "failed to remove $short"
done
