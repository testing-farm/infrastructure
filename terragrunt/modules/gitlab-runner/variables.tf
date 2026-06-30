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
  # 0.76.3 -> GitLab Runner 17.11.3 (last of the 17.x line). Includes the
  # Kubernetes informer (17.9+) which tracks build-pod status via watch instead
  # of polling `get pod`, the call behind the `Getting job pod status
  # Unauthorized` warnings. Staying on 17.x avoids the 18.0/19.0 breaking
  # changes.
  default = "0.76.3"
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
