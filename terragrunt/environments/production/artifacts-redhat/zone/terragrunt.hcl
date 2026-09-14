# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/zones?version=2.11.1"
}

locals {
  aws_tags = {
    FedoraGroup      = "ci"
    ServiceOwner     = "TFT"
    ServiceName      = "Artifacts"
    ServiceComponent = "Zone"
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

inputs = {
  zones = {
    "artifacts.testing.farm" = {
      comment = "Testing Farm artifacts public zone for NS delegation"
      tags    = local.aws_tags
    }
  }

  tags = local.aws_tags
}
