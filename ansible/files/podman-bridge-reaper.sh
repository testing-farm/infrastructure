#!/usr/bin/env bash
#
# podman-bridge-reaper -- remove leaked/orphaned podman bridge interfaces.
#
# netavark occasionally fails to delete a bridge during container teardown: the
# podman network config and IPAM lease get removed, but the kernel `podmanN`
# bridge survives as an orphan with no owning network. These accumulate on
# long-running workers and eventually collide with new networks --
#
#     netavark: create bridge: Netlink error: File exists (os error 17)
#
# -- failing container jobs with a spurious "permission denied" (exit 126).
#
# To stay safe the reaper deletes a bridge only when ALL of the following hold,
# so a live network is never touched:
#   * its name is `podmanN` (N >= 1; the default `podman0` is always kept),
#   * it is not the interface of any existing podman network, and
#   * it has no enslaved interface (no container is attached).
#
set -euo pipefail
shopt -s nullglob

# Bridge interfaces owned by an existing podman network must never be reaped.
# Listing the networks first means a failure here (e.g. podman is down) aborts
# the whole script via `set -e` -- we fail closed rather than risk treating a
# live bridge as an orphan.
network_names=$(podman network ls --quiet)

# The default `podman0` is always protected, even before any container attaches.
declare -A owned=([podman0]=1)
while read -r iface; do
    [[ -n $iface ]] && owned[$iface]=1
done < <(podman network inspect --format '{{.NetworkInterface}}' $network_names 2>/dev/null || true)

reaped=0
for path in /sys/class/net/podman[0-9]*; do
    bridge=${path##*/}

    [[ $bridge =~ ^podman[0-9]+$ ]] || continue   # numeric `podmanN` only
    [[ -v owned[$bridge] ]] && continue           # owned by a podman network

    members=("$path/brif/"*)
    (( ${#members[@]} )) && continue              # a container is attached

    if ip link delete "$bridge"; then
        echo "reaped orphan podman bridge: $bridge"
        reaped=$((reaped + 1))
    else
        echo "failed to delete orphan bridge: $bridge" >&2
    fi
done

echo "podman-bridge-reaper: reaped $reaped orphan bridge(s)"
