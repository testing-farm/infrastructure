# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws//?version=5.1.2"
}

locals {
  aws_tags = {
    FedoraGroup      = "ci"
    ServiceOwner     = "TFT"
    ServiceName      = "Artifacts"
    ServiceComponent = "SecurityGroup"
    ServicePhase     = "Prod"
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

  # Ingress restricted to approved Red Hat / VPN / worker paths
  ingress_with_source_security_group_id = [
    {
      rule                     = "ssh-tcp"
      source_security_group_id = "sg-0cb20f3b88c57fa30"
      description              = "SSH upload access from Red Hat workers"
    },
    {
      rule                     = "http-80-tcp"
      source_security_group_id = "sg-0cb20f3b88c57fa30"
      description              = "HTTP access from Red Hat workers"
    },
    {
      rule                     = "https-443-tcp"
      source_security_group_id = "sg-0cb20f3b88c57fa30"
      description              = "HTTPS access from Red Hat workers"
    },
  ]

  # Explicitly allow required outbound services for AWS API, package/image updates, DNS, and NTP
  # (NFS egress to mount target is managed separately by storage client SG)
  egress_rules       = ["https-443-tcp", "http-80-tcp", "dns-udp", "dns-tcp", "ntp-udp"]
  egress_cidr_blocks = ["0.0.0.0/0"]

  tags = local.aws_tags
}
