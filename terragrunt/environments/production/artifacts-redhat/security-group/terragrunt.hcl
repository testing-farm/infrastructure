# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws//?version=5.1.2"
}

locals {
  aws_tags = {
    # Authorization tag required by the network and compute deployment policies
    StorageBackend = "testing-farm-artifacts-redhat"
    # Legacy reporting tags
    AppCode          = "TFT-001"
    ServiceOwner     = "TFT"
    ServiceName      = "TestingFarm"
    ServiceComponent = "SecurityGroup"
    ServicePhase     = "Prod"
    # Red Hat IT unified tagging policy
    app-code          = "TFT-001"
    service-owner     = "TFT"
    service-name      = "TestingFarm"
    service-component = "SecurityGroup"
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

dependency "storage" {
  config_path = "../storage"

  mock_outputs = {
    vpc_id = "mock-vpc-id"
  }

  mock_outputs_merge_strategy_with_state  = "shallow"
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name        = "testing_farm_production_artifacts_redhat"
  description = "Security group for Testing Farm Red Hat artifacts server"
  vpc_id      = dependency.storage.outputs.vpc_id

  # Use the existing RH private-network access model for clients and administrators.
  # The instance has no public IP; allow only the frontend ports, not all worker SG traffic.
  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp", "http-80-tcp", "https-443-tcp"]

  # Explicitly allow required outbound services for AWS API, package/image updates, DNS, and NTP
  # (NFS egress to mount target is managed separately by storage client SG)
  egress_rules       = ["https-443-tcp", "http-80-tcp", "dns-udp", "dns-tcp", "ntp-udp"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}
