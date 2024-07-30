terraform {
  required_version = ">=1.2.0"

  required_providers {
    ansiblevault = {
      source  = "MeilleursAgents/ansiblevault"
      version = ">=2.2.0"
    }
    aws = {
      version = ">=4.0.0"
    }
    helm = {
      version = ">=2.9.0"
    }
  }
}

locals {
  # List of IPs which have access to guests provisioned by Artemis
  guests_ip_ranges = distinct(sort([
    for ip in concat(
      # Additional IPs from input variables
      var.additional_lb_source_ips,
      # Additional IPs from secrets
      # we accept a string with comma or newline delimited IPs
      split("\n", replace(trimspace(data.ansiblevault_path.guests_additional_ips.value), " ", "\n"))
    ) :
    # The IP can already have range defined
    length(regexall("/[0-9]+", ip)) > 0 ? ip : "${ip}/32"
    if ip != null
  ]))

  # List of IPs which have access to Artemis API
  artemis_lb_source_ranges = distinct(sort([
    for ip in concat(
      # Additional IPs from input variables
      var.additional_lb_source_ips,
      # Additional IPs from secrets
      # we accept a string with comma or newline delimited IPs
      split("\n", replace(trimspace(data.ansiblevault_path.artemis_additional_ips.value), " ", "\n"))
    ) :
    # The IP can already have range defined
    length(regexall("/[0-9]+", ip)) > 0 ? ip : "${ip}/32"
    if ip != null
  ]))
}

provider "ansiblevault" {
  vault_path  = var.ansible_vault_password_file
  root_folder = var.ansible_vault_secrets_root
}

provider "ansiblevault" {
  alias = "artemis_config"

  vault_path  = var.ansible_vault_password_file
  root_folder = var.config_root
}

resource "aws_security_group" "allow_guest_traffic" {
  name        = "${var.cluster_name}-${var.namespace}-allow-guest-traffic"
  description = "Allow traffic to Artemis guests"
  vpc_id      = "vpc-a4f084cd"
  provider    = aws.artemis_guests

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # allow guest traffic from workers and given list of addresses comming from variables
    cidr_blocks = concat(
      local.guests_ip_ranges,
      var.workers_ip_ranges
    )

    description = "Allow all inbound traffic"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    ipv6_cidr_blocks = ["::/0"]      #tfsec:ignore:aws-ec2-no-public-egress-sgr
    description      = "Allow all outbound traffic"
  }
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args = [
        "--profile",
        var.cluster_aws_profile,
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name
      ]
      command = "aws"
    }
  }
}

data "ansiblevault_path" "artemis_additional_ips" {
  path = var.ansible_vault_credentials
  key  = "artemis.additional_ips"
}

data "ansiblevault_path" "guests_additional_ips" {
  path = var.ansible_vault_credentials
  key  = "guests.additional_ips"
}

data "ansiblevault_path" "pool_access_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.profiles.fedora_us_east_2.access_key"
}

data "ansiblevault_path" "pool_secret_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.profiles.fedora_us_east_2.secret_key"
}

data "ansiblevault_path" "vault_password" {
  path = var.ansible_vault_credentials
  key  = "credentials.vault.password"
}

data "ansiblevault_path" "vault_ssh_key" {
  count = length(var.ssh_keys)

  provider = ansiblevault.artemis_config
  path     = var.ssh_keys[count.index].path
  key      = var.ssh_keys[count.index].key
}

resource "helm_release" "artemis" {
  name       = var.release_name
  repository = "https://testing-farm.gitlab.io/artemis-helm/dev"
  chart      = "artemis-core"
  version    = "0.0.4"
  namespace  = var.namespace

  create_namespace = true

  atomic        = true
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    sensitive(templatefile(
      "${path.module}/values.yaml.tftpl",
      {
        artemis_server_config = templatefile(
          "${var.config_root}/server.yaml.tftpl",
          {
            aws_access_key_id     = sensitive(data.ansiblevault_path.pool_access_key_aws.value)
            aws_secret_access_key = sensitive(data.ansiblevault_path.pool_secret_key_aws.value)
            ssh_keys = [
              for i in range(length(var.ssh_keys)) :
              merge(
                {
                  name  = var.ssh_keys[i].name
                  owner = var.ssh_keys[i].owner
                },
                yamldecode(sensitive(data.ansiblevault_path.vault_ssh_key[i].value))
              )
            ]
            aws_security_group_id = aws_security_group.allow_guest_traffic.id
          }
        )

        artemis_extra_files = merge(
          {
            for filename in var.config_extra_files :
            filename => file(
              fileexists("${var.config_root}/${filename}") ?
              "${var.config_root}/${filename}" : "${var.config_common}/${filename}"
            )
            }, {
            for template in var.config_extra_templates :
            template.target => templatefile(
              fileexists("${var.config_root}/${template.source}") ?
              "${var.config_root}/${template.source}" :
              "${var.config_common}/${template.source}",
              merge(
                { template_vars_sources = template.vars },
                [for varfile in template.vars : yamldecode(file(varfile))]...
              )
            )
          }
        )

        artemis_lb_source_ranges = concat(
          local.artemis_lb_source_ranges,
          var.workers_ip_ranges,
        )

        artemis_api_processes = var.api_processes
        artemis_api_threads   = var.api_threads
        artemis_api_domain    = var.api_domain

        artemis_connection_close_after_dispatch = var.connection_close_after_dispatch

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
    value = sensitive(data.ansiblevault_path.vault_password.value)
  }
}
