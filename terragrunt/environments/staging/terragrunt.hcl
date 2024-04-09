# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # staging EKS is hosted in this region
  aws_profile = "fedora_us_east_1"
  aws_region = "us-east-1"
  # AWS region of workers
  aws_profile_workers = "fedora_us_east_2"
  aws_region_workers = "us-east-2"
  # AWS region of Artemis guests
  aws_profile_guests = "fedora_us_east_2"
  aws_region_guests = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Stage"
  }
}

# shared inputs
inputs = {
  aws_profile        = local.aws_profile
  aws_profile_guests = local.aws_profile_guests
  route53_zone       = "testing-farm.io"
  resource_tags      = local.aws_tags
  cluster_name       = "testing-farm-staging"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {

  profile = "${local.aws_profile}"
  region = "${local.aws_region}"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}

provider "aws" {

  profile = "${local.aws_profile_guests}"
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

  profile = "${local.aws_profile_workers}"
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
