# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws//?version=5.1.2"
}

# Terraform cannot work well with multiple providers, so generate it here
# https://github.com/gruntwork-io/terragrunt/issues/1095
generate "provider-security-group" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {

  profile = "${local.common.inputs.aws_profile_workers}"
  region = "${local.common.inputs.aws_region_workers}"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.common.inputs.resource_tags)}
TAGS_EOF
)
  }
}
EOF
}

dependency "localhost" {
  config_path = "../../localhost"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    localhost_public_ips = ["127.0.0.1"]
  }
}

dependency "worker" {
  config_path = "../../worker-public"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    workers_ip_ranges = []
  }
}

inputs = {
  name        = "testing_farm_dev_server_${get_env("USER", "unknown")}"
  description = "Security group for Testing Farm server access"
  vpc_id      = "vpc-a4f084cd"

  ingress_cidr_blocks = concat(
    [for ip in dependency.localhost.outputs.localhost_public_ips : "${ip}/32"],
    dependency.worker.outputs.workers_ip_ranges
  )

  ingress_with_source_security_group_id = [
    {
      rule                     = "nomad-rpc-tcp"
      source_security_group_id = "sg-0040a2477d37dd6d0"
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "sg-0040a2477d37dd6d0"
    },
    {
      rule                     = "ssh-tcp"
      source_security_group_id = "sg-0040a2477d37dd6d0"
    }
  ]

  ingress_rules = ["ssh-tcp", "https-443-tcp", "http-80-tcp"]

  egress_rules = ["all-all"]

  # Testing Farm worker tags used to identify servers for this environment
  tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Server"
    "ServicePhase"     = "Dev"
  }
}
