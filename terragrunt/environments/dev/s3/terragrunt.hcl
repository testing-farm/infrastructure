# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

locals {
  # Automatically load environment-level variables
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

terraform {
  source = "tfr:///terraform-aws-modules/s3-bucket/aws//?version=2.4.0"
}

inputs = {
  bucket = "testing-farm_dev_s3_${get_env("USER", "unknown")}"

  tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Server"
    "ServicePhase"     = "Dev"
    "Name"             = "testing_farm_dev_s3_${get_env("USER", "unknown")}"
  }
}