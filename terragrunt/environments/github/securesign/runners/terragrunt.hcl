# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

locals {
  # Runners are hosted in this region
  aws_profile = "fedora_us_east_2"
  aws_region  = "us-east-2"

  # Version of the github actions runner
  # https://github.com/actions/runner/releases
  actions_runner_version = "2.317.0"

  # Fedora-Cloud-Base-AmazonEC2.x86_64-40-1.14-hvm-us-east-2-gp3-0
  ami = "ami-097f74237291abc07"

  # Runner instance type
  # vCPUs: 2, memory: 8GiB
  instance_type = "m7a.large"

  # VPC subnet
  subnet = "subnet-4f971734"

  # GitHub owner
  owner = basename(dirname(get_parent_terragrunt_dir()))

  # Use json to pass a map to the provider
  # https://github.com/gruntwork-io/terragrunt/issues/1961
  aws_tags = {
    ServiceOwner     = "TFT"
    ServiceName      = "GitHub"
    ServiceComponent = "Runner"
    ServicePhase     = "Prod"
    FedoraGroup      = "ci"
    Name             = "github_runner_${local.owner}"
  }
}

# Shared inputs
inputs = {
  name                   = local.aws_tags.Name
  aws_profile            = local.aws_profile
  aws_region             = local.aws_region
  aws_tags               = local.aws_tags
  route53_zone           = "testing-farm.io"
  resource_tags          = local.aws_tags
  actions_runner_version = local.actions_runner_version
  ami                    = local.ami
  instance_type          = local.instance_type
  subnet                 = local.subnet
  owner                  = local.owner
}

# Create terraform cloud workspace
terraform {
  before_hook "terraform_cloud_project" {
    commands = ["apply", "init", "import", "plan"]
    execute = [
      "terraform-cloud",
      "create-workspace", "--ignore-existing",
      "github-${local.owner}-${replace(path_relative_to_include(), "/", "-")}"
    ]
  }
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
      name = "github-${local.owner}-${replace(path_relative_to_include(), "/", "-")}"
    }
  }
}
EOF
}
