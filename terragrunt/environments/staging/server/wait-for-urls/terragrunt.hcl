# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Use url_wait module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separate repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../../modules//url_wait"
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

# Ensure we start waiting after the DNS records were created
dependency "dns" {
  config_path  = "../dns"
  skip_outputs = true
}

inputs = {
  # URLs to wait for after deployment of the server
  urls = [
    "api.staging.testing-farm.io/v0.1/about",
    "internal.api.staging.testing-farm.io/v0.1/about",
    "tmt.staging.testing-farm.io"
  ]
}
