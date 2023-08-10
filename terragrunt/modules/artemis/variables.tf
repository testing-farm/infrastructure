variable "release_name" {
  description = "Name of the installed release"
  type        = string
  default     = "artemis"
}

variable "namespace" {
  description = "Namespace to deploy the application to"
  type        = string
  default     = "default"
}

variable "config_common" {
  description = "Path to configuration directory containing common files across environments."
  type        = string
  default     = "./environments/common/config"
}

variable "config_root" {
  description = "Path of the artemis configuration directory."
  type        = string
}

variable "config_extra_files" {
  description = "List of files to include with artemis configuration."
  type        = list(string)
  default = [
    "ARTEMIS_HOOK_AWS_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_AZURE_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_BEAKER_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_OPENSTACK_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_ROUTE.py",
  ]
}

variable "config_extra_templates" {
  description = "List of files to template and include with artemis configuration."
  type = list(object({
    source = string
    target = string
    vars   = list(string)
  }))
}

variable "ssh_keys" {
  description = "SSH keys to configure artemis with"
  type = list(object({
    name  = string
    owner = string
    path  = string
    key   = string
  }))
  default = [{
    name  = "master-key"
    owner = "artemis"
    path  = "master-key.yaml"
    key   = ""
  }]
}

variable "additional_lb_source_ips" {
  description = "List of additional IP addresses"
  type        = list(string)
  default     = ["127.0.0.1"]
}

variable "localhost_access" {
  description = "Add localhost access to Artemis and guests."
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Artemis container image tag"
  type        = string
  default     = "latest"
}

variable "api_processes" {
  description = "Desired number of API service processes"
  type        = number
  default     = 1
}

variable "api_threads" {
  description = "Number of threads of API service"
  type        = number
  default     = 1
}

variable "api_domain" {
  description = "Domain the API service should be available on"
  type        = string
  default     = ""
}

variable "connection_close_after_dispatch" {
  description = "When enabled, broker connection will be forcefully closed after every message dispatch."
  type        = bool
  default     = true
}

variable "db_schema_revision" {
  description = "Database schema revision to use"
  type        = string
  default     = "head"
}

variable "worker_replicas" {
  description = "Number of worker replicas"
  type        = number
  default     = 5
}

variable "worker_processes" {
  description = "Number of worker processes"
  type        = number
  default     = 12
}

variable "worker_threads" {
  description = "Number of worker threads"
  type        = number
  default     = 4
}

variable "worker_extra_env" {
  description = "Extra environment variables for worker"
  type        = list(map(string))
  default     = []
}

variable "resources" {
  description = "Configure resources for pods"
  type        = map(map(map(string)))
  default     = {}

  validation {
    condition = alltrue([
      for key, val in var.resources :
      contains([
        "artemis_api",
        "artemis_dispatcher",
        "artemis_initdb",
        "artemis_init_containers",
        "artemis_scheduler",
        "artemis_worker",
        "rabbitmq",
        "postgresql",
        "postgresql_exporter",
        "redis",
        "redis_exporter"
      ], key) &&
      alltrue([
        for quota, resources in val :
        contains(["limits", "requests"], quota) &&
        alltrue([
          for resource in keys(resources) :
          contains(["cpu", "memory"], resource)
        ])
      ])
    ])
    error_message = "Unknown key in 'resources'."
  }
}

variable "ansible_vault_password_file" {
  description = "Path to ansible vault password file."
  type        = string
}

variable "ansible_vault_credentials" {
  description = "Path to ansible vault-encrypted credentials."
  type        = string
}

variable "ansible_vault_secrets_root" {
  description = "Path to the root directory with ansible vault secrets."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_aws_region" {
  description = "Default region of the EKS cluster."
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Certificate authority data of the EKS cluster."
  type        = string
}

variable "route53_zone" {
  description = "Route 53 zone name of the deployment."
  type        = string
}
