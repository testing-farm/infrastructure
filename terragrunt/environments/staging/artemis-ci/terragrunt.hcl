# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common       = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  artemis      = read_terragrunt_config("../artemis/terragrunt.hcl")
  route53_zone = local.common.inputs.route53_zone
  # Generate a random namespace for the deployment
  namespace = "artemis-${uuid()}"

  mocked_cluster_certificate_authority_data = "bW9jay1jbHVzdGVyLWNlcnRpZmljYXRlCg==" # pragma: allowlist secret
}

# Use eks module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separete repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//artemis"
}

dependency "localhost" {
  config_path = "../localhost"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    localhost_public_ip = "127.0.0.1"
  }
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
  cluster_certificate_authority_data = dependency.eks.outputs.cluster.cluster_certificate_authority_data != null ? dependency.eks.outputs.cluster.cluster_certificate_authority_data : local.mocked_cluster_certificate_authority_data
  cluster_aws_profile                = local.common.inputs.aws_profile
  guests_aws_profile                 = local.common.inputs.aws_profile_guests

  # Strip `testing-farm-` from the cluster name as use that to construct the artemis API domain name.
  # For example for `testing-farm-production` cluster that would be `artemis.production.testing-farm.io`
  api_domain = "artemis.${trimprefix(dependency.eks.outputs.cluster.cluster_name, "testing-farm-")}-${local.namespace}.${local.common.inputs.route53_zone}"

  release_name = local.artemis.inputs.release_name
  namespace    = local.namespace
  image_tag    = "v0.0.69"

  # Enable access from localhost
  additional_lb_source_ips = [dependency.localhost.outputs.localhost_public_ip]

  # Testing Farm worker tags used to identify workers for this environment
  testing_farm_worker_tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Worker"
    "ServicePhase"     = "StageCI"
  }

  ansible_vault_password_file = local.artemis.inputs.ansible_vault_password_file
  ansible_vault_credentials   = local.artemis.inputs.ansible_vault_credentials
  ansible_vault_secrets_root  = local.artemis.inputs.ansible_vault_secrets_root

  # point the config root to the staging artemis instance
  config_root        = "${get_parent_terragrunt_dir()}/artemis/config"
  config_extra_files = local.artemis.inputs.config_extra_files

  # point vars to the staging artemis instance
  config_extra_templates = [{
    source = local.artemis.inputs.config_extra_templates[0].source
    target = local.artemis.inputs.config_extra_templates[0].target
    vars   = ["${get_parent_terragrunt_dir()}/artemis/config/variables_images.yaml"]
  }]


  ssh_keys = local.artemis.inputs.ssh_keys

  api_processes = local.artemis.inputs.api_processes
  api_threads   = local.artemis.inputs.api_threads

  worker_extra_env = local.artemis.inputs.worker_extra_env

  worker_replicas  = local.artemis.inputs.worker_replicas
  worker_processes = local.artemis.inputs.worker_processes
  worker_threads   = local.artemis.inputs.worker_threads

  resources = local.artemis.inputs.resources
}
