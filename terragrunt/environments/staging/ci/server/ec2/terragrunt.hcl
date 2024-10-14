# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  server = read_terragrunt_config("../../../server/ec2/terragrunt.hcl")
  # get_working_dir is empty during plan, make sure we read the generated ignition file only during apply
  butane_file = "${get_terragrunt_dir()}/server.ign"
  user_data   = fileexists(local.butane_file) ? base64encode(file(local.butane_file)) : base64encode("error: butane file not generated")
}

terraform {
  source = "tfr:///terraform-aws-modules/ec2-instance/aws//?version=5.6.1"
}

dependency "security-group" {
  config_path = "../security-group"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    security_group_id = "mock-security-group-id"
  }

  mock_outputs_merge_strategy_with_state = "shallow"
}

inputs = {
  # fedora-coreos-39.20240407.2.0-x86_64
  ami = local.server.inputs.ami

  instance_type               = local.server.inputs.instance_type
  key_name                    = local.server.inputs.key_name
  subnet_id                   = local.server.inputs.subnet_id
  associate_public_ip_address = local.server.inputs.associate_public_ip_address
  enable_volume_tags          = local.server.inputs.enable_volume_tags

  user_data = local.user_data

  vpc_security_group_ids = [dependency.security-group.outputs.security_group_id]

  user_data_replace_on_change = local.server.inputs.user_data_replace_on_change

  root_block_device = local.server.inputs.root_block_device

  metadata_options = local.server.inputs.metadata_options

  # Testing Farm worker tags used to identify servers for this environment
  tags = merge(local.server.inputs.tags, {
    "ServicePhase" = "StageCI"
    "Name"         = "testing_farm_stage_server_${local.common.inputs.staging_ci_suffix}"
  })

  # Add ebs block device
  ebs_block_device = [{
    device_name           = local.server.inputs.ebs_block_device[0].device_name
    volume_type           = local.server.inputs.ebs_block_device[0].volume_type
    volume_size           = local.server.inputs.ebs_block_device[0].volume_size
    delete_on_termination = local.server.inputs.ebs_block_device[0].delete_on_termination
    tags = merge(local.server.inputs.ebs_block_device[0].tags, {
      Name         = "testing_farm_stage_server_${local.common.inputs.staging_ci_suffix}_data"
      ServicePhase = "StageCI"
    })
  }]
}
