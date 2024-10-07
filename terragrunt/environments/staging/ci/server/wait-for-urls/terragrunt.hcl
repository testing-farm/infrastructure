# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

# Use url_wait module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separete repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../../../modules//url_wait"
}

dependency "dns" {
  config_path  = "../dns"
  skip_outputs = true
}

inputs = {
  urls = local.common.inputs.wait_urls
}
