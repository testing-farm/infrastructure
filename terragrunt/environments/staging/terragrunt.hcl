# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # staging environment is hosted in this region
  aws_region        = "us-east-1"
  aws_region_guests = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = jsonencode({
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Stage"
  })
}

# shared inputs
inputs = {
  aws_region        = local.aws_region
  aws_region_guests = local.aws_region_guests
  route53_zone      = "testing-farm.io"
  cluster_name      = "testing-farm-staging"
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
provider "aws" {

  region = "${local.aws_region_guests}"
  alias = "artemis_guests"

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
  # for artemis-ci disable the block, we use local backend for it
  disable  = path_relative_to_include() == "artemis-ci" ? true : false
  contents = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "staging-${path_relative_to_include()}"
    }
  }
}
EOF
}
