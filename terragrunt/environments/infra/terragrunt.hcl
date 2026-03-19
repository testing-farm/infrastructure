# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # infra EKS is hosted in this region
  aws_profile = "fedora_us_east_2"
  aws_region  = "us-east-2"

  aws_tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Infra"
  }
}

# Create terraform cloud workspace
terraform {
  before_hook "before_hook" {
    commands = ["apply", "init", "import", "plan"]
    execute = [
      "terraform-cloud",
      "create-workspace", "--ignore-existing", "infra-${replace(path_relative_to_include(), "/", "-")}"
    ]
  }
}

# shared inputs for AWS-based modules
inputs = {
  aws_profile   = local.aws_profile
  route53_zone  = "testing-farm.io"
  resource_tags = local.aws_tags
  cluster_name  = "testing-farm-infra"
}

# Generate AWS provider only for eks and gitlab-runner paths
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  disable   = startswith(path_relative_to_include(), "eks") || startswith(path_relative_to_include(), "gitlab-runner") ? false : true
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
EOF
}

# Generate provider configuration for all configured modules
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "infra-${replace(path_relative_to_include(), "/", "-")}"
    }
  }
}
EOF
}
