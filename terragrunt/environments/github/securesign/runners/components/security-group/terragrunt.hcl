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

inputs = {
  name        = local.common.inputs.name
  description = "Security group for Testing Farm GitHub runner"
  vpc_id      = "vpc-a4f084cd"

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp"]

  egress_rules = ["all-all"]

  tags = local.common.inputs.aws_tags
}
