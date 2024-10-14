# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common     = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  repository = basename(get_terragrunt_dir())
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws//?version=5.6.1"
}

dependency "security-group" {
  config_path = "../../components/security-group"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    security_group_id = "mock-security-group-id"
  }

  mock_outputs_merge_strategy_with_state = "shallow"
}

dependency "key-pair" {
  config_path = "../../components/key-pair"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    key_pair_name = "mock-key-pair-name"
  }

  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  ami = local.common.inputs.ami

  instance_type               = local.common.inputs.instance_type
  key_name                    = dependency.key-pair.outputs.key_pair_name
  subnet_id                   = local.common.inputs.subnet
  associate_public_ip_address = true
  enable_volume_tags          = false

  vpc_security_group_ids = [dependency.security-group.outputs.security_group_id]

  root_block_device = [{
    encrypted = true
  }]

  metadata_options = {
    http_tokens = "required"
  }

  tags = local.common.inputs.aws_tags

  user_data = templatefile("${get_parent_terragrunt_dir()}/user_data.sh.tfpl", {
    version    = local.common.inputs.actions_runner_version,
    owner      = local.common.inputs.owner,
    repository = local.repository,
    token = run_cmd(
      "--terragrunt-quiet",
      "github", "worker-registration-token", local.common.inputs.owner, local.repository
    )
  })

  user_data_replace_on_change = true

  # Add ebs block device
  ebs_block_device = [{
    device_name           = "/dev/xvdf"
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    tags                  = local.common.inputs.aws_tags
  }]
}
