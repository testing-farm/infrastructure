include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../..//modules/gitlab/project"
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  project_name = "nomad-server-redhat"
}
