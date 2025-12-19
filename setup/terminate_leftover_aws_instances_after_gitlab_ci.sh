#!/bin/bash -e

#
# Cleanup leftover AWS instances after GitLab CI jobs in public ranch.
#

DRY_RUN=false
OLDER_THAN=4  # By default 4 hours

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS] OLDER_THAN_HOURS"
      echo
      echo "Options:"
      echo "  --dry-run    List instances that would be removed but do not remove them"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      OLDER_THAN=$1
      if [[ ! "$OLDER_THAN" =~ ^[0-9]+$ ]]; then
          echo "Error: Argument must be a positive integer (hours)"
          exit 1
      fi
      shift
      ;;
  esac
done

OLDER_THAN_SECONDS=$((OLDER_THAN * 60 * 60))

# The region for cleanup, by default all our EC2 instances are in 'us-east-2'
REGION=${AWS_REGION:-us-east-2}
# NOTE: our profile names use underscores, replace it here
REGION="${REGION//-/_}"

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
echo "Instance ID         Launch Time              State"
jq -r '.InstanceId + " " + .LaunchTime + " " + .State.Name' <<< "$instances_to_delete"

[ $DRY_RUN == true ] && exit 0

echo ""
for instance_id in $(jq -r '.InstanceId' <<< "$instances_to_delete"); do
    echo "Terminating $instance_id"
    $AWS_EC2 terminate-instances --instance-ids "$instance_id"
done
