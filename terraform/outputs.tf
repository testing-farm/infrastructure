output "artemis_api_domain" {
  value = module.artemis.api_domain
}

output "artemis_lb_source_ranges" {
  value     = module.artemis.lb_source_ranges
  sensitive = true
}
