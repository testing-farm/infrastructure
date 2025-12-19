#!/bin/bash -e

#
# Cleanup leftover AWS instances after GitLab CI jobs in public ranch.
#

# The region for cleanup, by default all our EC2 instances are in 'us-east-2'
REGION=${AWS_REGION:-us-east-2}
# NOTE: our profile names use underscores, replace it here
REGION="${REGION//-/_}"

#
# By default 4 hours, can be changed with parameter passed to the script.
#
[ -z "$1" ] && OLDER_THAN=4 || OLDER_THAN=$1
if [[ ! "$OLDER_THAN" =~ ^[0-9]+$ ]]; then
    echo "Error: Argument must be a positive integer (hours)"
    exit 1
fi
OLDER_THAN_SECONDS=$((OLDER_THAN * 60 * 60))

# Helper for running aws ec2 command
AWS_EC2="aws --profile fedora_$REGION ec2 --output json"

instances=$($AWS_EC2 describe-instances --filters "Name=tag:ServicePhase,Values=StageCI")

# Check if there are instances to terminate
if [ -z "$instances" ]; then
  echo "No instances found for cleanup."
  exit 0
fi

# Filter only instances older than $OLDER_THAN hours
instances_to_delete=$(jq -r --arg older_than_seconds "$OLDER_THAN_SECONDS" \
    '.Reservations.[].Instances.[] | select((now - (.LaunchTime | split(".")[0] + "Z" | fromdateiso8601)) > ($older_than_seconds | tonumber))' <<< $instances)

# Check again if there are instances to terminate
if [ -z "$instances_to_delete" ]; then
  echo "No instances found for cleanup."
  exit 0
fi

echo "AWS instances with ServicePhase=StageCI tag and older than $OLDER_THAN hours"
echo "Instance ID         Launch Time"
jq -r '.InstanceId + " " + .LaunchTime' <<< "$instances_to_delete"

echo ""
for instance_id in $(jq -r '.InstanceId' <<< "$instances_to_delete"); do
    echo "Terminating $instance_id"
    $AWS_EC2 terminate-instances --instance-ids "$instance_id"
done
