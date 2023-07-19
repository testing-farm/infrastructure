terraform {
  required_version = ">=1.0.9"
  required_providers {
    helm = {
      version = ">=2.9.0"
    }
  }
}

locals {
  api_domain = length(helm_release.artemis.metadata) > 0 ? var.api_domain : null
}

resource "helm_release" "artemis" {
  name       = var.release_name
  repository = "https://testing-farm.gitlab.io/artemis-helm/dev"
  chart      = "artemis-core"
  version    = "0.0.3"
  namespace  = var.namespace

  atomic        = true
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    sensitive(templatefile(
      "${path.module}/values.yaml.tftpl",
      {
        artemis_server_config = var.server_config
        artemis_extra_files   = var.extra_files

        artemis_lb_source_ranges = var.lb_source_ranges

        artemis_api_processes = var.api_processes
        artemis_api_threads   = var.api_threads
        artemis_api_domain    = var.api_domain

        artemis_connection_close_after_dispatch = var.connection_close_after_dispatch

        artemis_route_guest_request_retries     = var.route_guest_request_retries
        artemis_route_guest_request_min_backoff = var.route_guest_request_min_backoff
        artemis_route_guest_request_max_backoff = var.route_guest_request_max_backoff

        artemis_db_schema_revision = var.db_schema_revision

        artemis_worker_extra_env = var.worker_extra_env
        artemis_worker_replicas  = var.worker_replicas
        artemis_worker_processes = var.worker_processes
        artemis_worker_threads   = var.worker_threads

        artemis_image_tag = var.image_tag

        artemis_api_resources             = try(var.resources.artemis_api, {})
        artemis_dispatcher_resources      = try(var.resources.artemis_dispatcher, {})
        artemis_initdb_resources          = try(var.resources.artemis_initdb, {})
        artemis_init_containers_resources = try(var.resources.artemis_init_containers, {})
        artemis_scheduler_resources       = try(var.resources.artemis_scheduler, {})
        artemis_worker_resources          = try(var.resources.artemis_worker, {})
        rabbitmq_resources                = try(var.resources.rabbitmq, {})
        postgresql_resources              = try(var.resources.postgresql, {})
        postgresql_exporter_resources     = try(var.resources.postgresql_exporter, {})
        redis_resources                   = try(var.resources.redis, {})
        redis_exporter_resources          = try(var.resources.redis_exporter, {})
      }
    ))
  ]

  set_sensitive {
    name  = "artemis.vaultPassword"
    value = var.vault_password
  }
}
