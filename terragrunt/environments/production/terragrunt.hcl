# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # AWS region of EKS
  aws_region = "us-east-1"
  # AWS region of workers
  aws_region_workers = "us-east-2"
  # AWS region of Artemis guests
  aws_region_guests = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = jsonencode({
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Prod"
  })
}

# shared inputs
inputs = {
  aws_region         = local.aws_region
  aws_region_guests  = local.aws_region_guests
  aws_region_workers = local.aws_region_workers
  route53_zone       = "testing-farm.io"
  cluster_name       = "testing-farm-production"
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

provider "aws" {

  region = "${local.aws_region_workers}"
  alias = "workers"

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
