# Preserve the output interface of terraform-aws-modules/ec2-instance/aws v5.6.1.
output "id" {
  value = module.instance.id
}

output "arn" {
  value = module.instance.arn
}

output "capacity_reservation_specification" {
  value = module.instance.capacity_reservation_specification
}

output "instance_state" {
  value = module.instance.instance_state
}

output "outpost_arn" {
  value = module.instance.outpost_arn
}

output "password_data" {
  value = module.instance.password_data
}

output "primary_network_interface_id" {
  value = module.instance.primary_network_interface_id
}

output "private_dns" {
  value = module.instance.private_dns
}

output "public_dns" {
  value = module.instance.public_dns
}

output "public_ip" {
  value = module.instance.public_ip
}

output "private_ip" {
  value = module.instance.private_ip
}

output "ipv6_addresses" {
  value = module.instance.ipv6_addresses
}

output "tags_all" {
  value = module.instance.tags_all
}

output "spot_bid_status" {
  value = module.instance.spot_bid_status
}

output "spot_request_state" {
  value = module.instance.spot_request_state
}

output "spot_instance_id" {
  value = module.instance.spot_instance_id
}

output "ami" {
  value = module.instance.ami
}

output "availability_zone" {
  value = module.instance.availability_zone
}

output "iam_role_name" {
  value = module.instance.iam_role_name
}

output "iam_role_arn" {
  value = module.instance.iam_role_arn
}

output "iam_role_unique_id" {
  value = module.instance.iam_role_unique_id
}

output "iam_instance_profile_arn" {
  value = module.instance.iam_instance_profile_arn
}

output "iam_instance_profile_id" {
  value = module.instance.iam_instance_profile_id
}

output "iam_instance_profile_unique" {
  value = module.instance.iam_instance_profile_unique
}

output "root_block_device" {
  value = module.instance.root_block_device
}

output "ebs_block_device" {
  value = module.instance.ebs_block_device
}

output "ephemeral_block_device" {
  value = module.instance.ephemeral_block_device
}
