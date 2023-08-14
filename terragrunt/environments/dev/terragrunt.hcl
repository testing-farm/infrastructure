locals {
  # development environments are hosted in this region
  aws_region = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = jsonencode({
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Dev"
  })
}

# shared inputs
inputs = {
  aws_region   = local.aws_region
  route53_zone = "testing-farm.io"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {

  region = "${local.aws_region}"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${local.aws_tags}
TAGS_EOF
)
  }
}
EOF
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "local" {}
}
EOF
}
