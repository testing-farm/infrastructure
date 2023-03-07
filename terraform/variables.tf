variable "cluster_name" {
  description = "EKS cluster name to create."
  type        = string
}

variable "cluster_default_region" {
  description = "Default region for the EKS cluster."
  type        = string
}

variable "cluster_vpc_id" {
  description = "AWS VPC ID"
  type        = string
}

variable "cluster_subnets" {
  description = "Subnets to be used by the EKS cluster"
  type        = list(string)
}

variable "cluster_node_group_instance_types" { # tflint-ignore: terraform_typed_variables
  default = ["t3.medium"]
}

variable "cluster_node_group_disk_size" { # tflint-ignore: terraform_typed_variables
  default = 50
}

variable "cluster_node_group_scaling" { # tflint-ignore: terraform_typed_variables
  default = {
    desired_size = 1
    min_size     = 1
    max_size     = 1
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

variable "artemis_ssh_keys" {
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

variable "artemis_release_name" {
  description = "Name of the installed artemis release"
  type        = string
  default     = "artemis"
}

variable "artemis_namespace" {
  description = "Namespace to install Artemis to"
  type        = string
  default     = "default"
}

variable "artemis_config_common" {
  description = "Path to configuration directory containing common files across environments."
  type        = string
  default     = "./environments/common/config"
}

variable "artemis_config_root" {
  description = "Path of the artemis configuration directory."
  type        = string
}

variable "artemis_config_extra_files" {
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

variable "artemis_config_extra_templates" {
  description = "List of files to template and include with artemis configuration."
  type = list(object({
    source = string
    target = string
    vars   = list(string)
  }))
}

variable "artemis_additional_lb_source_ips" {
  description = "List of additional IP addresses"
  type        = list(string)
  default     = ["127.0.0.1"]
}

variable "artemis_api_processes" {
  description = "Number of worker processes"
  type        = number
  default     = 4
}

variable "artemis_api_threads" {
  description = "Number of worker threads"
  type        = number
  default     = 4
}

variable "artemis_worker_replicas" {
  description = "Number of worker replicas"
  type        = number
  default     = 5
}

variable "artemis_worker_processes" {
  description = "Number of worker processes"
  type        = number
  default     = 12
}

variable "artemis_worker_threads" {
  description = "Number of worker threads"
  type        = number
  default     = 4
}

variable "artemis_worker_extra_env" {
  description = "Extra environment variables for worker"
  type        = list(map(string))
  default     = []
}

variable "artemis_guest_security_group_id" {
  description = "Security group for aws guests"
  type        = string
}

variable "resources" {
  description = "Configure resources for pods"
  type        = map(map(map(string)))
  default     = {}
}
