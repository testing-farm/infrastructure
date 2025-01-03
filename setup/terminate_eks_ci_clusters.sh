#!/bin/bash -e

#
# Cleanup leftover EKS clusters from AWS.
#

# Region of the development instances
region=${CLUSTERS_REGION:-us_east_2}
aws_eks="aws --profile fedora_$region eks"

# These clusters are protected
protected_clusters="testing-farm testing-farm-production testing-farm-staging"

# Clusters to remove
CLUSTERS_REGEX=${CLUSTERS_REGEX:-testing-farm-gitlab-ci}

# Clusters delta seconds for cleanup, will not cleanup clusters newer than this
CLUSTERS_CLEANUP_DELTA_SECONDS=${CLUSTERS_CLEANUP_DELTA_SECONDS:-7200}

# Get current epoch
CURRENT_EPOCH=$(date +%s)

# Get the list of eks clusters created by CI
clusters=$($aws_eks list-clusters | jq -r '.clusters[]' | grep -E "$CLUSTERS_REGEX")

# Check if there are instances to terminate
if [ -z "$clusters" ]; then
  echo "No EKS clusters found for cleanup."
  exit 0
fi

# Terminate node groups
for cluster in $clusters; do
  # Ignore protected clusters
  if grep -E "$cluster" <<< "$protected_clusters"; then
      echo "[!] Refusing to remove protected cluster '$cluster'"
      continue
  fi

  # Ignore clusters not older than CLUSTERS_CLEANUP_DELTA_SECONDS seconds
  creation_epoch=$($aws_eks describe-cluster --name "$cluster" --query "cluster.createdAt" --output text | cut -d. -f1)
  age_seconds=$((CURRENT_EPOCH - creation_epoch))
  if [ $age_seconds -le $CLUSTERS_CLEANUP_DELTA_SECONDS ]; then
      echo "Ignoring cluster '$cluster', age $age_seconds seconds"
      continue
  fi

  (
      echo "[+] Processing cluster '$cluster', age $age_seconds seconds"
      for nodegroup in $($aws_eks list-nodegroups --cluster-name $cluster | jq -r .nodegroups[]); do
          echo "[+] Deleting nodegroup '$nodegroup'"
          $aws_eks delete-nodegroup --cluster-name $cluster --nodegroup-name $nodegroup
          echo "[+] Waiting for nodegroup '$nodegroup' deletion"
          $aws_eks wait nodegroup-deleted --cluster-name $cluster --nodegroup-name $nodegroup
      done
      echo "[+] Deleting cluster $cluster"
      $aws_eks delete-cluster --name $cluster
      echo "[+] Waiting for cluster $cluster deletion"
      $aws_eks wait cluster-deleted --name $cluster
  ) &
done

wait
