terraform {
  required_version = ">=1.2.0"

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">=16.5.0"
    }
  }
}

provider "gitlab" {
  token = var.gitlab_token
}

locals {
  all_schedule_variables = flatten([
    for index, schedule in var.schedules : [
      for name, value in schedule.variables : {
        index = index
        name  = name
        value = value
      }
    ]
  ])
}

resource "gitlab_pipeline_schedule" "schedule" {
  for_each = { for index, schedule in var.schedules : index => schedule }

  project     = var.project_id
  description = each.value.description
  ref         = each.value.git_ref
  cron        = each.value.cron_schedule
  active      = each.value.active
}

resource "gitlab_pipeline_schedule_variable" "schedule_variable" {
  for_each = {
    for var in local.all_schedule_variables : "${var.index}-${var.name}" => var
  }

  project = var.project_id
  # In the GitLab Terraform provider, the id of a pipeline schedule is a composite identifier `project_id:schedule_id`
  pipeline_schedule_id = split(":", gitlab_pipeline_schedule.schedule[each.value.index].id)[1]
  key                  = each.value.name
  value                = each.value.value
}
