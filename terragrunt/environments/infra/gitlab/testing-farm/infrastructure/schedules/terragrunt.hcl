# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../../../modules//gitlab/schedules"
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  project_id   = "17754827"
  schedules = [
    {
      description   = "Redeploy staging environment"
      git_ref       = "main"
      cron_schedule = "0 0 * * sat"
      variables = {
        "SCHEDULED_JOB" : "redeploy/staging"
      }
    },
    {
      description   = "Run make cleanup/staging/ci"
      git_ref       = "main"
      cron_schedule = "0 */8 * * *"
      variables = {
        "SCHEDULED_JOB" : "cleanup/staging/ci"
      }
    }
  ]
}
