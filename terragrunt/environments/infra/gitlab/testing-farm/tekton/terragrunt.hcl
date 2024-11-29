include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../..//modules/gitlab/project"
}

dependency "integrations_group" {
  config_path = "../integrations/"
  mock_outputs = {
    group_id = "123"
  }
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  project_name = "tekton"
  namespace_id = dependency.integrations_group.outputs.group_id
}
