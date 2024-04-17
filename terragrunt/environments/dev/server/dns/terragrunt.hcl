# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

dependency "ec2" {
  config_path = "../ec2"

  # Configure mock outputs for the `validate` command that are returned when there are no outputs available (e.g the
  # module hasn't been applied yet.
  mock_outputs_allowed_terraform_commands = ["validate"]
  mock_outputs = {
    public_dns = "mocked dns"
  }
}

inputs = {
  zone_name = local.common.inputs.route53_zone
  records_jsonencoded = jsonencode([
    {
      name = "api.dev-${get_env("USER")}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "internal.api.dev-${get_env("USER")}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "artifacts.dev-${get_env("USER")}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns,
      ]
    },
    {
      name = "nomad.dev-${get_env("USER")}"
      type = "CNAME"
      ttl  = 60
      records = [
        dependency.ec2.outputs.public_dns
      ]
    }
  ])
}
