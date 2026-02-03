output "artemis_api_domain" {
  value = var.api_domain
}

output "guests_aws_profile" {
  value = var.guests_aws_profile
}

output "guests_security_group_id" {
  value = var.enable_multiple_security_groups ? [aws_security_group.allow_guest_traffic_additional[0].id, aws_security_group.allow_guest_traffic_workers[0].id] : [aws_security_group.allow_guest_traffic[0].id]
}

output "namespace" {
  value = var.namespace
}

output "api_lb_security_group_id" {
  description = "Security group ID for the Artemis API load balancer"
  value       = aws_security_group.artemis_api_lb.id
}
