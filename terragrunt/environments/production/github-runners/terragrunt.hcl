# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Use worker module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separete repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//worker"
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

inputs = {
  worker_tags = local.common.inputs.github_runner_tags
}
