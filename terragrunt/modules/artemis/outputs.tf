output "artemis_api_domain" {
  value = var.api_domain
}

output "guests_aws_region" {
  value = var.guests_aws_region
}

output "guests_security_group_id" {
  value = aws_security_group.allow_guest_traffic.id
}
