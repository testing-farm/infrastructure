output "artemis_api_domain" {
  value = var.api_domain
}

output "guests_aws_profile" {
  value = var.guests_aws_profile
}

output "guests_security_group_id" {
  value = var.enable_nested_security_groups ? aws_security_group.allow_guest_traffic_nested[0].id : aws_security_group.allow_guest_traffic[0].id
}

output "namespace" {
  value = var.namespace
}
