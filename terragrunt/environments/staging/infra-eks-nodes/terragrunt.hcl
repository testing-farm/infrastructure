# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Use worker module to query infra EKS node public IPs
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//worker"
}

inputs = {
  worker_tags = {
    "kubernetes.io/cluster/testing-farm-infra" = "owned"
  }
}
