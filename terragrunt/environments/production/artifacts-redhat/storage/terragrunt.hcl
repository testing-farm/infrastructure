# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../modules//artifacts-storage"
}

locals {
  aws_tags = {
    FedoraGroup      = "ci"
    ServiceOwner     = "TFT"
    ServiceName      = "Artifacts"
    ServiceComponent = "Storage"
    ServicePhase     = "Prod"
  }
}

# Override provider generator to target the Red Hat AWS account in us-east-1
generate "provider_us_east_2" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  profile             = "redhat_us_east_1_storage"
  region              = "us-east-1"
  allowed_account_ids = ["727920394381"]

  default_tags {
    tags = jsondecode(<<TAGS_EOF
${jsonencode(local.aws_tags)}
TAGS_EOF
)
  }
}
EOF
}

# Override backend generator to sanitize workspace name (no slashes)
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "production-artifacts-redhat-storage"
    }
  }
}
EOF
}

inputs = {
  bucket_name = "testing-farm-artifacts-redhat"
  vpc_id      = "vpc-008152fcfb0333f30"
  subnet_id   = "subnet-036ad213c3fb0eb7e"
  tags        = local.aws_tags
}
