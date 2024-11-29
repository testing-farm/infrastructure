variable "gitlab_token" {
  description = "The GitLab access token."
  type        = string
}

variable "group_name" {
  description = "The name of the group in GitLab."
  type        = string
}

variable "group_path" {
  description = "The path to the group in GitLab."
  type        = string
}

variable "description" {
  description = "The description of the group in GitLab."
  type        = string
  default     = null
}
