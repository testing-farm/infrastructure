#!/bin/bash -e

#
# Terminate all instances Artemis has created in the development environment.
#
# This is required when running in CI to mitigate race condition when trying
# to remove the security group which is managed by Terraform.
#

ARTEMIS_DEPLOYMENT="${ARTEMIS_DEPLOYMENT:-artemis}"
ENVIRONMENT="$1"

error() {
    echo -e "\033[0;31m[E] $*\033[0m"
    exit 1
}

[ -z "$ENVIRONMENT" ] && error "Environment name required!"
[[ "$ENVIRONMENT" =~ (dev|staging|production) ]] || error "Unsupported environment '$ENVIRONMENT'!"

# Extra check for production
if [ "$ENVIRONMENT" == "production" ]; then
    read -rp "This will remove all production guests. Are you sure you wish to continue? (y/n) " reply
    if [ "$reply" != "y" ]; then
        exit 1
    fi
fi

# Terraform environment directory
environment="$PROJECT_ROOT/terragrunt/environments/$ENVIRONMENT/${ARTEMIS_DEPLOYMENT}"

[ ! -d "$environment" ] && error "No Artemis deployment found in environment '$ENVIRONMENT'"

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
