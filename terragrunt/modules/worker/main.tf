terraform {
  required_version = ">=1.2.0"

  required_providers {
    aws = {
      version = ">=4.0.0"
    }
  }
}

locals {
  # List of tags used to identify Testing Farm worker AWS.
  # Terraform doesn't directly support iterating over a map for dynamic filters in a data source.
  workers_tags_list = [for key, value in var.worker_tags : {
    key   = key
    value = value
  }]

  # List of IP ranges of the Testing Farm workers.
  workers_ip_ranges = length(data.aws_instances.workers.ids) > 0 ? [for public_ip in data.aws_instances.workers.public_ips : "${public_ip}/32"] : []

  # List of instance IDs
  workers_instance_ids = length(data.aws_instances.workers.ids) > 0 ? [for id in data.aws_instances.workers.ids : id] : []
}

# Testing Farm workers, used to provide IPs which have access to Artemis API endpoint
data "aws_instances" "workers" {
  dynamic "filter" {
    for_each = local.workers_tags_list

    content {
      name   = "tag:${filter.value.key}"
      values = [filter.value.value]
    }
  }

  instance_state_names = ["running"]
}
