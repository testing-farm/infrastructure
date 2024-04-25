#!/bin/bash -e

#
# Cleanup leftover EKS clusters from AWS.
#

# Region of the development instances
region="us-east-2"
aws_eks="aws --profile fedora_us_east_2 eks"

CLUSTER_REGEX="${CLUSTER_REGEX:-testing-farm-gitlab-ci}"

# Get the list of eks clusters created by CI
clusters=$($aws_eks list-clusters | jq -r '.clusters[]' | grep -E "$CLUSTER_REGEX")

# Check if there are instances to terminate
if [ -z "$clusters" ]; then
  echo "No EKS clusters found for cleanup."
  exit 0
fi

# Terminate node groups
for cluster in $clusters; do
  echo "[+] Processing cluster '$cluster'"
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
done
