variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate authority data for the EKS cluster."
  type        = string
}

variable "aws_profile" {
  description = "Name of AWS profile for EKS authentication."
  type        = string
}

variable "gitlab_token" {
  description = "GitLab access token with create_runner scope."
  type        = string
  sensitive   = true
}

variable "gitlab_url" {
  description = "URL of the GitLab instance."
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_group_id" {
  description = "GitLab group ID to register the runner for."
  type        = number
}

variable "runner_description" {
  description = "Description of the runner in GitLab."
  type        = string
  default     = "testing-farm-infra EKS runner"
}

variable "release_name" {
  description = "Name of the Helm release."
  type        = string
  default     = "gitlab-runner"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the runner into."
  type        = string
  default     = "gitlab-runner"
}

variable "chart_version" {
  description = "Version of the gitlab-runner Helm chart."
  type        = string
  default     = "0.71.0"
}

variable "concurrent" {
  description = "Maximum number of concurrent jobs."
  type        = number
  default     = 10
}

variable "check_interval" {
  description = "How often the runner checks for new jobs (seconds)."
  type        = number
  default     = 3
}

variable "runner_tags" {
  description = "List of tags for the runner."
  type        = list(string)
  default     = ["testing-farm"]
}

variable "run_untagged" {
  description = "Whether the runner should pick up untagged jobs."
  type        = bool
  default     = false
}
