output "api_domain" {
  value = local.api_domain
}

output "lb_source_ranges" {
  value       = var.lb_source_ranges
  description = "List of IP ranges Artemis accepts connections from"
  sensitive   = true
}
