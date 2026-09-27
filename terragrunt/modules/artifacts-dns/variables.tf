variable "zone_id" {
  description = "Hosted-zone ID supplied by the zone deployment"
  type        = string
}

variable "zone_name" {
  description = "Hosted-zone domain used to qualify artifact record names without an AWS lookup"
  type        = string
}

variable "records_jsonencoded" {
  description = "JSON-encoded artifact record definitions supplied by Terragrunt"
  type        = string
}
