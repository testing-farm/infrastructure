# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # production EKS is hosted in this region
  aws_profile_us_east_1 = "fedora_us_east_1"
  aws_region_us_east_1  = "us-east-1"
  # AWS region hosting workers and guests
  aws_profile_us_east_2 = "fedora_us_east_2"
  aws_region_us_east_2  = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Prod"
  }
  # Testing Farm worker tags used to identify workers for this environment
  worker_tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Worker"
    "ServicePhase"     = "Prod"
  }
  # Testing Farm github runner tags used to identify github runners for this environment
  github_runner_tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "GitHub"
    "ServiceComponent" = "Runner"
    "ServicePhase"     = "Prod"
  }
}

# shared inputs
inputs = {
  aws_profile         = local.aws_profile_us_east_1
  aws_profile_guests  = local.aws_profile_us_east_2
  aws_region_workers  = local.aws_region_us_east_2
  aws_profile_workers = local.aws_profile_us_east_2
  route53_zone        = "testing-farm.io"
  resource_tags       = local.aws_tags
  worker_tags         = local.worker_tags
  github_runner_tags  = local.github_runner_tags
  cluster_name        = "testing-farm-production"
}

# Provider for artemis and eks, has 2 regions
generate "provider-multi-region" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  disable   = startswith(path_relative_to_include(), "eks") || strcontains(path_relative_to_include(), "artemis") ? false : true
  contents  = <<EOF
provider "aws" {

  profile = "${local.aws_profile_us_east_1}"
  region = "${local.aws_region_us_east_1}"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}

provider "aws" {

  profile = "${local.aws_profile_us_east_2}"
  region = "${local.aws_region_us_east_2}"
  alias = "artemis_guests"

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}

provider "aws" {

  profile = "${local.aws_profile_us_east_2}"
  region = "${local.aws_region_us_east_2}"
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

# Provider for all other modules, except eks and artemis
generate "provider_us_east_2" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  disable   = startswith(path_relative_to_include(), "eks") || strcontains(path_relative_to_include(), "artemis") ? true : false
  contents  = <<EOF
provider "aws" {

  profile = "${local.aws_profile_us_east_2}"
  region = "${local.aws_region_us_east_2}"

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
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "production-${path_relative_to_include()}"
    }
  }
}
EOF
}
