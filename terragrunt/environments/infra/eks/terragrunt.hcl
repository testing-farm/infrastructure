# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Use eks module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separete repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//eks"
}

inputs = {
  # cluster_name is set in the parent
  eks_version = 1.32

  # aws_profile is set in the parent
  # route53_zone is set in the parent

  vpc_id = "vpc-0f6baa3d6bae8d912"
  # Private subnets routed through NAT gateway for stable egress IP
  subnets                   = ["subnet-03c46e32396b50643", "subnet-0c31de6da86b6770f"]
  nat_gateway               = true
  node_group_ami_type       = "AL2023_x86_64_STANDARD"
  addons_before_compute     = true
  node_group_instance_types = ["r6a.2xlarge"]
  node_group_disk_size      = 500
  node_group_scaling = {
    desired_size = 2
    max_size     = 6
    min_size     = 2
  }
}
