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
