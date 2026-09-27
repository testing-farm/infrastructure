# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../modules//artifacts-server"
}

locals {
  aws_tags = {
    # Authorization tag required by the compute deployment policy
    StorageBackend = "testing-farm-artifacts-redhat"
    # Legacy reporting tags
    AppCode          = "TFT-001"
    ServiceOwner     = "TFT"
    ServiceName      = "TestingFarm"
    ServiceComponent = "ArtifactsServer"
    ServicePhase     = "Prod"
    Name             = "testing_farm_production_artifacts_redhat"
    # Red Hat IT unified tagging policy
    app-code          = "TFT-001"
    service-owner     = "TFT"
    service-name      = "TestingFarm"
    service-component = "ArtifactsServer"
    service-phase     = "prod"
    map-migrated      = "migZZ8SDMVO5T"
  }
}

# Override provider generator to target the Red Hat AWS account in us-east-1
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  profile             = "redhat_us_east_1_storage"
  region              = "us-east-1"
  allowed_account_ids = ["727920394381"]

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}
EOF
}

dependency "storage" {
  config_path = "../storage"

  mock_outputs = {
    subnet_id                = "subnet-mock"
    instance_profile_name    = "mock-instance-profile"
    client_security_group_id = "sg-mock-client"
  }

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "security-group" {
  config_path = "../security-group"

  mock_outputs = {
    security_group_id = "sg-mock-security-group"
  }

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name = "testing_farm_production_artifacts_redhat"

  # TFT-4795 default-branch releases use CI_COMMIT_SHORT_SHA; MR uploads use a separate suffix.
  ami_name                    = "artifacts-bootc-x86_64-*"
  ami_name_regex              = "^artifacts-bootc-x86_64-[0-9a-f]{8}$"
  instance_type               = "c6in.2xlarge"
  key_name                    = "tft-redhat-artifacts-admin"
  subnet_id                   = dependency.storage.outputs.subnet_id
  associate_public_ip_address = false
  enable_volume_tags          = false

  iam_instance_profile = dependency.storage.outputs.instance_profile_name
  vpc_security_group_ids = [
    dependency.security-group.outputs.security_group_id,
    dependency.storage.outputs.client_security_group_id,
  ]

  root_block_device = [{
    encrypted   = true
    volume_type = "gp3"
    volume_size = 50
  }]

  metadata_options = {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}
