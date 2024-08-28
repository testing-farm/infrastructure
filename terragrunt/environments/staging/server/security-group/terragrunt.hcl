# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

terraform {
  source = "tfr:///terraform-aws-modules/security-group/aws//?version=5.1.2"
}

inputs = {
  name        = "testing_farm_staging_server"
  description = "Security group for Testing Farm server access"
  vpc_id      = "vpc-a4f084cd"

  # server is open to the world, lock down needs to happen on nginx side
  ingress_cidr_blocks = ["0.0.0.0/0"],

  ingress_rules = ["ssh-tcp", "https-443-tcp", "http-80-tcp"]

  egress_rules = ["all-all"]

  # Testing Farm worker tags used to identify servers for this environment
  tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Server"
    "ServicePhase"     = "Stage"
  }
}
