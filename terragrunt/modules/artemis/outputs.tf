output "artemis_api_domain" {
  value = var.api_domain
}

output "guests_aws_profile" {
  value = var.guests_aws_profile
}

output "guests_security_group_id" {
  value = aws_security_group.allow_guest_traffic.id
}

output "namespace" {
  value = var.namespace
}
