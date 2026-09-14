# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

locals {
  aws_tags = {
    FedoraGroup      = "ci"
    ServiceOwner     = "TFT"
    ServiceName      = "Artifacts"
    ServiceComponent = "DNS"
    ServicePhase     = "Prod"
  }
}

# Override provider generator to target the Fedora AWS account in us-east-1 for Route53
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  profile             = "fedora_us_east_1"
  region              = "us-east-1"
  allowed_account_ids = ["125523088429"]

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}
EOF
}

dependency "zone" {
  config_path = "../zone"

  mock_outputs = {
    route53_zone_zone_id = {
      "artifacts.testing.farm" = "Z0123456789ABCDEF"
    }
  }

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "ec2" {
  config_path = "../ec2"

  mock_outputs = {
    private_ip = "10.0.0.1"
  }

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  zone_id = dependency.zone.outputs.route53_zone_zone_id["artifacts.testing.farm"]

  records_jsonencoded = jsonencode([
    {
      name = "redhat"
      # NOTE (TFT-4797): Deliberately using an A record to EC2 private_ip instead of CNAME.
      # The artifact server is private-only (accessible via Red Hat / VPN network paths),
      # and VPN/internal clients cannot be assumed to resolve AWS-private hostnames.
      # A direct A record to the private IP avoids private DNS resolution issues.
      type = "A"
      ttl  = 60
      records = [
        dependency.ec2.outputs.private_ip,
      ]
    }
  ])
}
