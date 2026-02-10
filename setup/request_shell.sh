#!/bin/bash -eu

#
# Connect to the shell of a running Testing Farm request.
#

error() {
    echo -e "\033[0;31m[E] $*\033[0m"
    exit 1
}

command -v nomad &>/dev/null || error "Command 'nomad' not found. Please run infrastructure setup."

REQUEST_ID=$(sed -nE 's/.*([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}).*/\1/p' <<< "$1")

[ -z "$REQUEST_ID" ] && error "Valid request ID is parameter is required."
[ -z "$TESTING_FARM_API_URL" ] && error "TESTING_FARM_API_URL not set in the environment."

JOB=$(curl -s "${TESTING_FARM_API_URL}/requests/${REQUEST_ID}" | jq -r .notes[0].message | sed 's/.*\///;s/%2F/\//')
[ "$JOB" == "null" ] && error "Could not find Nomad job in the given request."

ALLOCATION=$(nomad job allocs -json "$JOB" | jq -r 'sort_by(.CreateIndex) | last(.[])')
[ -z "$ALLOCATION" ] && error "Could not find allocation for Nomad job '$JOB', make sure you use correct ranch."

STATUS=$(echo "$ALLOCATION" | jq -r .ClientStatus)
[ "$STATUS" != "running" ] && error "Last allocation for job '$JOB' has status '$STATUS', it is not running, giving up."

TASK=$(echo "$ALLOCATION" | jq -r .TaskGroup)
ALLOC_ID=$(echo "$ALLOCATION" | jq -r .ID)

nomad alloc exec -i -t -task "$TASK" "$ALLOC_ID" podman exec -it "$REQUEST_ID" bash
