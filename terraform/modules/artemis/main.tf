resource "helm_release" "artemis" {
  name          = var.release_name
  repository    = "https://gitlab.com/api/v4/projects/30361172/packages/helm/dev"
  chart         = "artemis-core"
  version       = "0.0.3"
  namespace     = var.namespace

  atomic        = true
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values        = [
    templatefile(
      "${path.module}/values.yml.tftpl",
      {
        artemis_server_config             = var.server_config
        artemis_extra_files               = var.extra_files

        artemis_lb_source_ranges          = var.lb_source_ranges

        artemis_api_processes             = var.api_processes
        artemis_api_threads               = var.api_threads
        artemis_api_domain                = var.api_domain

        artemis_worker_replicas           = var.worker_replicas
        artemis_worker_processes          = var.worker_processes
        artemis_worker_threads            = var.worker_threads

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
    )
  ]

  set_sensitive {
    name  = "artemis.vaultPassword"
    value = var.vault_password
  }
}
