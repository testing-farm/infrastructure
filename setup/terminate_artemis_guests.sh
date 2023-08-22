#!/bin/bash -e

#
# Terminate all instances Artemis has created in the development environment.
#
# This is required when running in CI to mitigate race condition when trying
# to remove the security group which is managed by Terraform.
#

error() {
    echo -e "\033[0;31m[E] $*\033[0m"
    exit 1
}

[ -z "$1" ] && error "Environment name required!"
[[ "$1" =~ (dev|staging) ]] || error "Unsupported environment '$1'!"

# Terraform environment directory
environment="$PROJECT_ROOT/terragrunt/environments/$1/artemis"

[ ! -d "$environment" ] && error "No Artemis deployment found in environment '$1'"

# Region of the development instance
region=$(TERRAGRUNT_WORKING_DIR=$environment terragrunt output --raw guests_aws_region)

grep -q "No outputs found" <<< "$region" && error "No Artemis guests region found, environment not deployed?"

# Set the security group ID
security_group_id=$(TERRAGRUNT_WORKING_DIR=$environment terragrunt output --raw guests_security_group_id)

# Get the instance IDs associated with the specified security group
instance_ids=$(aws --region $region ec2 describe-instances --filters Name=instance.group-id,Values=$security_group_id --query 'Reservations[].Instances[].InstanceId' --output text)

# Check if there are instances to terminate
if [ -z "$instance_ids" ]; then
  echo "No instances found with security group $security_group_id"
  exit 0
fi

# Terminate instances
echo "Terminating instances with security group $security_group_id"
for instance_id in $instance_ids; do
  echo "Terminating instance $instance_id"
  aws --region $region ec2 terminate-instances --instance-ids "$instance_id"
done
