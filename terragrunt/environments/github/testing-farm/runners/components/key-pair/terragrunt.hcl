# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

terraform {
  source = "tfr:///terraform-aws-modules/key-pair/aws//?version=2.0.3"
}

inputs = {
  name        = local.common.inputs.name
  description = "Keypair for Testing Farm SecureSign GitHub runner"

  key_name           = local.common.inputs.name
  create_private_key = true

  tags = local.common.inputs.aws_tags
}
