variable "gitlab_token" {
  description = "The GitLab access token."
  type        = string
}

variable "project_name" {
  description = "The name of the project in GitLab."
  type        = string
}

variable "description" {
  description = "The description of the project in GitLab."
  type        = string
  default     = null
}

variable "namespace_id" {
  description = "The ID of the namespace to create the project in. Default to testing-farm group."
  type        = number
  default     = 5515434
}

variable "default_branch" {
  description = "The name of the default branch"
  type        = string
  default     = "main"
}
