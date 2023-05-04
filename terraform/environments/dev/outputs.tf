output "aws_region" {
  value = local.aws_region
}

output "artemis_api_domain" {
  value = module.devel-cluster.artemis_api_domain
}

output "artemis_security_group_id" {
  value = resource.aws_security_group.allow_guest_traffic.id
}
