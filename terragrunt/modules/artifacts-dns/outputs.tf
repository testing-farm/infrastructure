# Preserve the output interface of terraform-aws-modules/route53/aws v2.11.1 records.
output "route53_record_name" {
  description = "The name of the record"
  value       = { for key, record in aws_route53_record.this : key => record.name }
}

output "route53_record_fqdn" {
  description = "FQDN built using the zone domain and name"
  value       = { for key, record in aws_route53_record.this : key => record.fqdn }
}
