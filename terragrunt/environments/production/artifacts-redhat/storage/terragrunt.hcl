# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../modules//artifacts-storage"
}

locals {
  aws_tags = {
    # Legacy reporting tags
    AppCode          = "TFT-001"
    ServiceOwner     = "TFT"
    ServiceName      = "TestingFarm"
    ServiceComponent = "Storage"
    ServicePhase     = "Prod"
    # Red Hat IT unified tagging policy
    app-code          = "TFT-001"
    service-owner     = "TFT"
    service-name      = "TestingFarm"
    service-component = "Storage"
    service-phase     = "prod"
    map-migrated      = "migZZ8SDMVO5T"
  }
}

# Override provider generator to target the Red Hat AWS account in us-east-1
generate "provider" {
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

inputs = {
  bucket_name = "testing-farm-artifacts-redhat"
  vpc_id      = "vpc-008152fcfb0333f30"
  subnet_id   = "subnet-036ad213c3fb0eb7e"
  name_prefix = "testing-farm-artifacts-redhat"
}
