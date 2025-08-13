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
  cluster_name = get_env("TF_VAR_cluster_name", "testing-farm-dev-${get_env("USER", "unknown")}")
  eks_version  = 1.28

  # aws_profile is set in the parent
  # route53_zone is set in the parent

  vpc_id                    = "vpc-0f6baa3d6bae8d912"
  subnets                   = ["subnet-010f90da92f36876e", "subnet-0a704a759f7671044"]
  node_group_instance_types = ["c5.2xlarge"]
  node_group_disk_size      = 500
  node_group_scaling = {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}
