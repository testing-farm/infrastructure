#!/bin/bash -e

#
# Cleanup security groups from AWS matching given regular expression.
#

error() { echo "Error: $*"; exit 1; }

PREFIX="$1"
[ -z "$PREFIX" ] && error "Enter search prefix for the SGs"

region=${AWS_REGION:-us_east_2}

export aws_ec2="aws --profile fedora_$region ec2"

mapfile -t security_groups < <($aws_ec2 describe-security-groups --filters "Name=group-name,Values=${PREFIX}" | jq -c '.SecurityGroups[]')

remove_security_group() {
  name=$(echo "$1" | jq -r .GroupName)
  group_id=$(echo "$1" | jq -r .GroupId)
  # ingress_rules=$(echo "$1" | jq -r .IpPermissionsEgress[])

  # for rule in $egress_rules; do
  #   aws ec2 revoke-security-group-egress \
  #     --group-id "$sg_id" \
  #     --ip-permissions "$rule"
  # done

  echo "Removing SG '$name'"
  if ! $aws_ec2 delete-security-group --group-id "$group_id"; then
    echo "Could not remove: $1"
  fi
}
export -f remove_security_group

printf "%s\n" "${security_groups[@]}" | parallel -n1 remove_security_group
