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

variable "server_config" {
  description = "Server configuration"
  type        = string
}

variable "extra_files" {
  description = "List of additional files to be included in the configuration directory"
  type        = map(string)
  default     = {}
}

variable "vault_password" {
  description = "Ansible vault password"
  type        = string
}

variable "lb_source_ranges" {
  description = "List of IP address ranges to be white-listed by the load balancer"
  type        = list(string)
  default     = []
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
