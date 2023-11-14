#!/bin/bash -e

#
# Delete leftover namespaces from Kubernetes older then OLDER_THAN hours.
# By default 4 hours, can be changed with parameter passed to the script.
#
[ -z "$1" ] && OLDER_THAN=4 || OLDER_THAN=$1
OLDER_THAN_SECONDS=$((OLDER_THAN * 60 * 60))

echo "[+] Removing artemis-* namespaces older then $OLDER_THAN hours"
kubectl get namespaces -o json | \
    jq -r ".items[] | select(.metadata.name | startswith(\"artemis-\")) | select((now - (.metadata.creationTimestamp | fromdateiso8601)) > $OLDER_THAN_SECONDS) | .metadata.name" | \
    xargs -rt kubectl delete namespace
