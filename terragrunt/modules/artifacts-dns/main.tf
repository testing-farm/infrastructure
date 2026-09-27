locals {
  records = jsondecode(var.records_jsonencoded)
}

# Use the supplied ID directly: dependency mocks must not trigger AWS zone lookups
# during the first plan, before the separate zone workspace has been applied.
resource "aws_route53_record" "this" {
  for_each = { for record in local.records : "${record.name} ${record.type}" => record }

  zone_id         = var.zone_id
  name            = "${each.value.name}.${var.zone_name}"
  type            = each.value.type
  ttl             = each.value.ttl
  records         = each.value.records
  allow_overwrite = false
}
