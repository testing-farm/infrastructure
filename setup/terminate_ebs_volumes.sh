#!/bin/bash -e

#
# Cleanup orphaned EBS volumes from AWS.
#
# When EKS clusters are deleted, Kubernetes PVC-backed EBS volumes are left
# behind because the EBS CSI driver controller can no longer process the
# delete finalizer. This script finds and removes these orphaned volumes.
#
# Volumes are identified by the `CSIVolumeName` tag which is set by the
# AWS EBS CSI driver when provisioning PVCs.
#

DRY_RUN=false
OLDER_THAN=${OLDER_THAN:-24}  # Hours, default 24

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo
      echo "Options:"
      echo "  --dry-run    List volumes that would be removed but do not remove them"
      echo
      echo "Environment variables:"
      echo "  OLDER_THAN   Only remove volumes older than this many hours (default: 24)"
      echo "  AWS_REGION   AWS region to clean up (default: us_east_2)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Regions to clean up
REGIONS=${AWS_REGION:-us_east_2}

OLDER_THAN_SECONDS=$((OLDER_THAN * 60 * 60))
CURRENT_EPOCH=$(date +%s)

for REGION in $REGIONS; do
  AWS_EC2="aws --profile fedora_$REGION ec2 --output json"

  echo "[+] Searching for orphaned EBS volumes in $REGION (older than ${OLDER_THAN}h)"

  # Find available (unattached) volumes with the CSIVolumeName tag
  volumes=$($AWS_EC2 describe-volumes \
    --filters "Name=status,Values=available" "Name=tag-key,Values=CSIVolumeName" \
    --query 'Volumes[].{VolumeId:VolumeId,CreateTime:CreateTime,Size:Size,VolumeType:VolumeType}')

  if [ "$(jq length <<< "$volumes")" -eq 0 ]; then
    echo "[+] No orphaned volumes found in $REGION"
    continue
  fi

  # Filter volumes older than OLDER_THAN hours
  volumes_to_delete=$(jq -r --arg older_than "$OLDER_THAN_SECONDS" --arg now "$CURRENT_EPOCH" \
    '[.[] | select(($now | tonumber) - (.CreateTime | split(".")[0] + "Z" | fromdateiso8601) > ($older_than | tonumber))]' \
    <<< "$volumes")

  count=$(jq length <<< "$volumes_to_delete")

  if [ "$count" -eq 0 ]; then
    echo "[+] No volumes older than ${OLDER_THAN}h found in $REGION"
    continue
  fi

  total_gb=$(jq '[.[].Size] | add' <<< "$volumes_to_delete")
  echo "[+] Found $count orphaned volumes ($total_gb GB) in $REGION"

  if [ "$DRY_RUN" = true ]; then
    jq -r '.[] | "\(.VolumeId) \(.CreateTime) \(.Size)GB \(.VolumeType)"' <<< "$volumes_to_delete"
    continue
  fi

  # Delete volumes with limited parallelism to avoid API rate limiting
  echo "[+] Deleting $count volumes in $REGION"
  deleted=0
  failed=0

  for volume_id in $(jq -r '.[].VolumeId' <<< "$volumes_to_delete"); do
    if $AWS_EC2 delete-volume --volume-id "$volume_id" 2>/dev/null; then
      deleted=$((deleted + 1))
    else
      echo "[!] Failed to delete $volume_id"
      failed=$((failed + 1))
    fi
  done

  echo "[+] Deleted $deleted volumes, $failed failed in $REGION"
done
