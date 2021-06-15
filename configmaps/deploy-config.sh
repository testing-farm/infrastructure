#!/bin/bash

CONFIGURATION=artemis

# kubectl does not like these temp files ...
rm -f $CONFIGURATION/*~

kubectl ns artemis

# make sure configuration config map exists or update it
if ! kubectl get configmap/artemis-configuration &>/dev/null; then
    # create configmap
    info "creating configuration config map from 'configuration' directory"
    if ! kubectl create configmap artemis-configuration --from-file=$CONFIGURATION; then
        error "Failed to create configmap, cannot continue"
        return 1
    fi
else
    # update configmap
    info "updating configuration config map from 'configuration' directory"
    configmap=$(mktemp)
    if ! kubectl create --dry-run -o json configmap artemis-configuration --from-file=$CONFIGURATION > $configmap; then
        error "Failed to update configmap, cannot continue"
        exit 1
    fi
    kubectl replace -f $configmap
    rm -f $configmap
fi

kubectl rollout restart deployment artemis-worker
