variable "gitlab_token" {
  description = "The GitLab access token."
  type        = string
}

variable "project_id" {
  description = "The ID of the project in GitLab."
  type        = string
}

variable "schedules" {
  description = "A list of scheduled pipeline configurations"
  type = list(object({
    description   = string
    git_ref       = string
    cron_schedule = string
    active        = optional(bool, true)
    variables     = optional(map(string), {})
  }))
}
