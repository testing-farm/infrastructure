# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  # Generate a suffix for the deployment
  name = "staging-${get_env("STAGING_CI_SUFFIX")}"
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
      name = local.name
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "ui-backend.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "api.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "internal.api.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "artifacts.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "nomad.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns
      ]
    },
    {
      name = "tmt.${local.name}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns
      ]
    }
  ])
}
