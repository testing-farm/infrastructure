# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  suffix = local.common.inputs.staging_ci_suffix
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

dependency "ec2" {
  config_path = "../ec2"

  mock_outputs = {
    public_dns = "mocked dns"
  }

  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  zone_name = local.common.inputs.route53_zone
  records_jsonencoded = jsonencode([
    {
      name = "staging-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "ui-backend-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "api-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "internal-api-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "artifacts-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "nomad-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns
      ]
    },
    {
      name = "tmt-${local.suffix}.staging-ci"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns
      ]
    }
  ])
}
