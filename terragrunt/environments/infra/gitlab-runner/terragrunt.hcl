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

# Generate provider configurations — EKS-specific auth belongs here, not in the
# generic gitlab-runner module.
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "gitlab_token" {
  type      = string
  sensitive = true
}

variable "cluster_endpoint" {
  type = string
}

variable "cluster_certificate_authority_data" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "aws_profile" {
  type = string
}

provider "gitlab" {
  token = var.gitlab_token
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["--profile", var.aws_profile, "eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["--profile", var.aws_profile, "eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}
EOF
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
  chart_version      = "0.76.3"

  concurrent     = 50
  check_interval = 3
  runner_tags    = ["testing-farm"]
  run_untagged   = true
}
