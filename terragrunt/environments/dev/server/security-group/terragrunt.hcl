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
generate "provider" {
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

dependency "artemis" {
  config_path = "../../artemis"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    localhost_ip = "127.0.0.1"
  }

  # As we added this output to an existing setup, merging with remote state is needed or it will cause issues with existing deployments update
  # https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#dependency
  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  name        = "testing_farm_dev_server_${get_env("USER", "unknown")}"
  description = "Security group for SSH access from the developer machine"
  vpc_id      = "vpc-a4f084cd"

  ingress_cidr_blocks = ["${dependency.artemis.outputs.localhost_ip}/32"]
  ingress_rules       = ["ssh-tcp"]

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
