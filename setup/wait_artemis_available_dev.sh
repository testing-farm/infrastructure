#!/bin/bash -e

#
# Wait until Artemis works via its DNS hostname.
#
# This is required when running in CI to mitigate race condition when tests
# run sooner as Artemis is resolvable via DNS.
#

timeout=300
environment=$PROJECT_ROOT/terragrunt/environments/dev/artemis
hostname=$(TERRAGRUNT_WORKING_DIR=$environment terragrunt output --raw artemis_api_domain)

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
