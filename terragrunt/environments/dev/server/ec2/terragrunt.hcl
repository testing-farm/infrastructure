# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  # get_working_dir is empty during plan, make sure we read the generated ignition file only during apply
  butane_file = "${get_working_dir()}/server.ign"
  user_data   = fileexists(local.butane_file) ? base64encode(file(local.butane_file)) : base64encode("error: butane file not generated")
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws//?version=5.6.1"

  before_hook "before_hook" {
    commands = ["init", "apply", "plan"]
    execute  = ["butane", "-psd", get_env("PROJECT_ROOT"), "-o", "server.ign", "server.bu"]
  }
}

# Terraform cannot work well with multiple providers, so generate it here
# https://github.com/gruntwork-io/terragrunt/issues/1095
generate "provider-ec2" {
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

dependency "security-group" {
  config_path = "../security-group"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    security_group_id = "mock-security-group-id"
  }
}

inputs = {
  # fedora-coreos-39.20240407.2.0-x86_64
  ami = "ami-0c16645ea75d9e9b8"

  instance_type               = "m7a.medium"
  key_name                    = "testing-farm"
  subnet_id                   = "subnet-4f971734"
  associate_public_ip_address = true

  user_data              = local.user_data
  vpc_security_group_ids = [dependency.security-group.outputs.security_group_id]

  root_block_device = [{
    encrypted = true
  }]

  metadata_options = {
    http_tokens = "required"
  }

  # Testing Farm worker tags used to identify servers for this environment
  tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Server"
    "ServicePhase"     = "Dev"
    "Name"             = "testing_farm_dev_server_${get_env("USER", "unknown")}"
  }
}
