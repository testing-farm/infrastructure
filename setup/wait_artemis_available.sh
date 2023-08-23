#!/bin/bash -e

#
# Wait until Artemis works via its DNS hostname.
#
# This is required when running in CI to mitigate race condition when tests
# run sooner as Artemis is resolvable via DNS.
#

error() {
    echo -e "\033[0;31m[E] $*\033[0m"
    exit 1
}

[ -z "$1" ] && error "Environment name required!"

ARTEMIS_DEPLOYMENT=${ARTEMIS_DEPLOYMENT:-artemis}

timeout=300
environment="$PROJECT_ROOT/terragrunt/environments/$1/$ARTEMIS_DEPLOYMENT"

[ ! -d "$environment" ] && error "No Artemis deployment found in environment '$1'"

hostname=$(TERRAGRUNT_WORKING_DIR=$environment terragrunt output --raw artemis_api_domain)

if grep -q "No outputs found" <<< "$hostname"; then
    error "No Artemis hostname found, '$ARTEMIS_DEPLOYMENT' in environment '$1' not deployed?"
fi

echo "Waiting for Artemis API to be available via '$hostname'"

for seconds in $(seq 1 $timeout); do
    if curl --connect-timeout 1 -Lso /dev/null $hostname/v0.0.55/about; then
        echo "Artemis api domain '$hostname' was resolvable in ~$seconds seconds"
        exit 0
    fi
    sleep 1
done

echo "Artemis api domain '$hostname' was not resolvable in ~$timeout seconds"
exit 1
