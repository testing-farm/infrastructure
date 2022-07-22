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

module "artemis" {
  source = "./modules/artemis"

  server_config = templatefile(
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

  extra_files = merge(
    {
      for filename in var.artemis_config_extra_files :
      filename => file(
        fileexists("${var.artemis_config_root}/${filename}") ?
          "${var.artemis_config_root}/${filename}" : "${var.artemis_config_common}/${filename}"
      )
    }, {
      for template in var.artemis_config_extra_templates :
        template.target => templatefile(
          fileexists("${var.artemis_config_root}/${template.source}") ?
            "${var.artemis_config_root}/${template.source}" :
            "${var.artemis_config_common}/${template.source}",
          merge(
            {template_vars_sources=template.vars},
            [for varfile in template.vars : yamldecode(file(varfile))]...
          )
      )
    }
  )

  vault_password = sensitive(data.ansiblevault_path.vault_password.value)

  lb_source_ranges = [
    for ip in concat(jsondecode(data.external.ansible_inventory.result.output), var.artemis_additional_lb_source_ips) :
    "${ip}/32"
    if ip != null
  ]

  api_processes    = var.artemis_api_processes
  api_threads      = var.artemis_api_threads

  worker_replicas  = var.artemis_worker_replicas
  worker_processes = var.artemis_worker_processes
  worker_threads   = var.artemis_worker_threads

  resources        = var.resources
}
