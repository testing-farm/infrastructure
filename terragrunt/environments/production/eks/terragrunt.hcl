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
  # cluster_name is set by direnv
  eks_version = 1.28

  # aws_profile is set in the parent
  # route53_zone is set in the parent

  vpc_id                    = "vpc-0896aedab4753e76f"
  subnets                   = ["subnet-0b84fdcd88b5803c2", "subnet-03089904253762f32", "subnet-029d836119c84a77e"]
  node_group_instance_types = ["c6a.2xlarge"]
  node_group_disk_size      = 500
  node_group_scaling = {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
}
