# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  sg = read_terragrunt_config("../../../server/security-group/terragrunt.hcl")
  staging_suffix = get_env("STAGING_CI_SUFFIX")
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws//?version=5.1.2"
}

inputs = {
  name        = "testing_farm_staging_${local.staging_suffix}_server"
  description = local.sg.inputs.description
  vpc_id      = local.sg.inputs.vpc_id

  ingress_cidr_blocks = local.sg.inputs.ingress_cidr_blocks

  ingress_rules = local.sg.inputs.ingress_rules

  egress_rules = local.sg.inputs.egress_rules

  tags = merge(local.sg.inputs.tags, {
    "ServicePhase"     = "StageCI"
  })
}
