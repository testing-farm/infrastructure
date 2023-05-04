#!/bin/bash -e

#
# Terminate all instances Artemis has created in the development environment.
#
# This is required when running in CI to mitigate race condition when trying
# to remove the security group which is managed by Terraform.
#

# Terraform environment directory
environment="$PROJECT_ROOT/terraform/environments/dev"

# Region of the development instance
region=$(terraform -chdir=$environment output --raw aws_region)

# Set the security group ID
security_group_id=$(terraform -chdir=$environment output --raw artemis_security_group_id)

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
