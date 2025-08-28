#!/bin/bash -e

#
# Cleanup security groups from AWS in public ranch.
#
# The cleanup is controlled by the yaml configuration defined in the CONFIG variable.
#
# Each list item defins a single cleanup workflow with the following parameters:
#
# * name
#
#   Search for security groups with given name.
#   A string with glob support to match multiple groups.
#   Example: 'artemis-guest-*' to match all guests created by Artemis
#
# Note that any failures in removing the group are ignored, this is by design because if the security group is still in use it will not be possible to remove it.
# Unfortunately security groups do not have timestamps to check on date, so we go the stupid way :(
#

# Cleanup configuration
CONFIG="
# Cleanup leftover security groups of Artemis guests
- name: artemis-guest-*

# Cleanup leftover dev server security groups
- name: testing_farm_dev_server_gitlab-ci-*

# Cleanup leftover staging server security groups
- name: testing_farm_staging_*_server-*
"

# The region for cleanup, by default all our EC2 instances are in 'us-east-2'
REGION=${AWS_REGION:-us_east_2}

# Helper for running aws ec2 command, exported because it is used in subprocesses launched by parallel
export AWS_EC2="aws --profile fedora_$REGION ec2"

# Remove a single security group, exported because it is used in subprocesses launched by parallel
remove_security_group() {
  sg_name=$(echo "$1" | jq -r .GroupName)
  group_id=$(echo "$1" | jq -r .GroupId)

  # TODO: fix later, not needed for the first version
  # ingress_rules=$(echo "$1" | jq -r .IpPermissionsEgress[])

  # for rule in $egress_rules; do
  #   aws ec2 revoke-security-group-egress \
  #     --group-id "$sg_id" \
  #     --ip-permissions "$rule"
  # done

  echo "Removing SG '$sg_name'"
  if ! $AWS_EC2 delete-security-group --group-id "$group_id"; then
    echo "Could not remove: $sg_name"
  fi
}
export -f remove_security_group

echo "[+] Starting leftover SGs cleanup"

# Iterate through all config items
for i in $(yq -r 'keys | join(" ")' <<< "$CONFIG"); do
  name=$(yq -r ".[$i].name" <<< "$CONFIG")

  # read security groups json to array, each item is on one line
  mapfile -t security_groups < <($AWS_EC2 describe-security-groups --filters "Name=group-name,Values=${name}" | jq -c '.SecurityGroups[]')

  # Wait for a minute to mitigate TFT-3644
  echo "[+] Waiting 1 minute to mitigate TFT-3644"
  sleep 60

  # remove the security groups in parallel, limit to max 4 parallel executions
  printf "%s\n" "${security_groups[@]}" | parallel --jobs 8 -n1 remove_security_group
done

# vim: set ft=sh ts=2 sw=2 et:
