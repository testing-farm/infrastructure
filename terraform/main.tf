terraform {
  backend "local" {}

  required_providers {
    ansiblevault = {
      source = "MeilleursAgents/ansiblevault"
    }
  }
}

provider "ansiblevault" {
  vault_path  = var.ansible_vault_password_file
  root_folder = var.ansible_vault_secrets_root
}

provider "ansiblevault" {
  alias       = "artemis_config"

  vault_path  = var.ansible_vault_password_file
  root_folder = var.artemis_config_root
}

provider "helm" {
  kubernetes {
    host                   = module.testing-farm-eks-devel.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.testing-farm-eks-devel.cluster.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = [
        "--region",
        var.cluster_default_region,
        "eks",
        "get-token",
        "--cluster-name",
        module.testing-farm-eks-devel.cluster.cluster_id
      ]
      command     = "aws"
    }
  }
}

data "ansiblevault_path" "pool_access_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.fedora.access_key"
}

data "ansiblevault_path" "pool_secret_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.fedora.secret_key"
}

data "ansiblevault_path" "vault_password" {
  path = var.ansible_vault_credentials
  key  = "credentials.vault.password"
}

data "ansiblevault_path" "vault_ssh_key" {
  count    = length(var.artemis_ssh_keys)

  provider = ansiblevault.artemis_config
  path     = var.artemis_ssh_keys[count.index].path
  key      = var.artemis_ssh_keys[count.index].key
}

data "external" "ansible_inventory" {
  # Parse public ips from ansible-inventory, and return dummy json, storing
  # the list as string. This is done due to the limitation of the `external`
  # data source not being able to parse complex JSON, only string->string
  # mapping. The list can be decoded from JSON, by calling `jsondecode` function
  # with the string stored in attribute `output` as its parameter.
  program = [
    "/bin/sh",
    "-c",
    "ansible-inventory --list | jq '[._meta.hostvars[].public_ip_address]' | jq -n --arg output \"$(cat)\" '{$output}'"
  ]
}

module "testing-farm-eks-devel" {
  source             = "./modules/eks"

  # NOTE: cluster_name is set by direnv
  cluster_name       = var.cluster_name

  aws_default_region = var.cluster_default_region
  vpc_id             = var.cluster_vpc_id

  cluster_subnets    = var.cluster_subnets
  cluster_version    = "1.21"
}

resource "helm_release" "artemis" {
  name          = var.artemis_release_name
  repository    = "https://gitlab.com/api/v4/projects/30361172/packages/helm/dev"
  chart         = "artemis-core"
  version       = "0.0.3"
  namespace     = var.artemis_namespace

  atomic        = true
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  lint          = true

  values        = [
    templatefile(
      "values.yml.tftpl",
      {
        artemis_server_config    = templatefile(
          "${var.artemis_config_root}/server.yml.tftpl",
          {
            aws_access_key_id     = sensitive(data.ansiblevault_path.pool_access_key_aws.value)
            aws_secret_access_key = sensitive(data.ansiblevault_path.pool_secret_key_aws.value)
            ssh_keys              = [
              for i in range(length(var.artemis_ssh_keys)) :
                merge(
                  {
                    name        = var.artemis_ssh_keys[i].name
                    owner       = var.artemis_ssh_keys[i].owner
                  },
                  yamldecode(sensitive(data.ansiblevault_path.vault_ssh_key[i].value))
                )
            ]
          }
        )

        artemis_extra_files      = {
          for filename in var.artemis_config_extra_files :
          filename => file("${var.artemis_config_root}/${filename}")
        }

        artemis_lb_source_ranges = [
          for ip in concat(jsondecode(data.external.ansible_inventory.result.output), var.artemis_additional_lb_source_ips) :
          "${ip}/32"
          if ip != null
        ]

        artemis_api_processes    = var.artemis_api_processes
        artemis_api_threads      = var.artemis_api_threads

        artemis_worker_replicas  = var.artemis_worker_replicas
        artemis_worker_processes = var.artemis_worker_processes
        artemis_worker_threads   = var.artemis_worker_threads

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
    value = data.ansiblevault_path.vault_password.value
  }
}
