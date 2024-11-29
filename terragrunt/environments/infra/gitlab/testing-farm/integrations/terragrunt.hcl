include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../..//modules/gitlab/group"
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  group_name   = "integrations"
  group_path   = "integrations"
  description  = "The subgroup for all integrations, such as tekton, GitLab CI, etc."
}
