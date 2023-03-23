output "artemis_api_domain" {
  value = module.staging-cluster.artemis_api_domain
}

output "artemis_lb_source_ranges" {
  value     = module.staging-cluster.artemis_lb_source_ranges
  sensitive = true
}
