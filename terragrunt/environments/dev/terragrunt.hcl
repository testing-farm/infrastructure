# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

# Create terraform cloud workspace
terraform {
  before_hook "terraform_cloud_project" {
    commands = ["apply", "init", "import", "plan"]
    execute = [
      "terraform-cloud",
      "create-workspace", "--ignore-existing",
      "dev-${get_env("USER", "unknown")}-${replace(path_relative_to_include(), "/", "-")}"
    ]
  }
}

locals {
  # development EKS is hosted in this region
  aws_profile = "fedora_us_east_2"
  aws_region  = "us-east-2"
  # AWS region of workers
  aws_profile_workers = "fedora_us_east_2"
  aws_region_workers  = "us-east-2"
  # AWS region of Artemis guests
  aws_profile_guests = "fedora_us_east_2"
  aws_region_guests  = "us-east-2"
  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Dev"
  }
  # Testing Farm worker tags used to identify workers for this environment
  worker_tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Worker"
    "ServicePhase"     = "Dev"
    "Developer"        = get_env("USER", "unknown")
  }
}

# shared inputs
inputs = {
  aws_profile         = local.aws_profile
  aws_profile_guests  = local.aws_profile_guests
  aws_region_workers  = local.aws_region_workers
  aws_profile_workers = local.aws_profile_workers
  route53_zone        = "testing-farm.io"
  resource_tags       = local.aws_tags
  worker_tags         = local.worker_tags
  # NOTE cluster_name is generated, see `eks/terragrunt.hcl`
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
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "dev-${get_env("USER", "unknown")}-${replace(path_relative_to_include(), "/", "-")}"
    }
  }
}
EOF
}
