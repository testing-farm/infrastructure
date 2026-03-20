# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))

  mocked_cluster_certificate_authority_data = "bW9jay1jbHVzdGVyLWNlcnRpZmljYXRlCg==" # pragma: allowlist secret
}

# Use gitlab-runner module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//gitlab-runner"
}

dependency "eks" {
  config_path = "../eks"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    cluster = {
      cluster_name                       = "mock-cluster-name"
      cluster_endpoint                   = "mock-cluster-endpoint"
      cluster_certificate_authority_data = local.mocked_cluster_certificate_authority_data
    }
  }
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster.cluster_certificate_authority_data
  aws_profile                        = local.common.inputs.aws_profile

  gitlab_token    = get_env("TF_VAR_gitlab_testing_farm_bot")
  gitlab_url      = "https://gitlab.com"
  gitlab_group_id = 5515434

  release_name       = "gitlab-runner"
  namespace          = "gitlab-runner"
  runner_description = "testing-farm-infra EKS runner"
  chart_version      = "0.71.0"

  concurrent     = 20
  check_interval = 3
  runner_tags    = ["testing-farm"]
  run_untagged   = true
}
