# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # development EKS is hosted in this region
  aws_region = "us-east-2"
  # AWS region of workers
  aws_region_workers = "us-east-2"
  # AWS region of Artemis guests
  aws_region_guests = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Dev"
  }
}

# shared inputs
inputs = {
  aws_region        = local.aws_region
  aws_region_guests = local.aws_region_guests
  route53_zone      = "testing-farm.io"
  resource_tags     = local.aws_tags
  # NOTE cluster_name is generated, see `eks/terragrunt.hcl`
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {

  region = "${local.aws_region}"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}

provider "aws" {

  region = "${local.aws_region_guests}"
  alias = "artemis_guests"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}

provider "aws" {

  region = "${local.aws_region_workers}"
  alias = "workers"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
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
