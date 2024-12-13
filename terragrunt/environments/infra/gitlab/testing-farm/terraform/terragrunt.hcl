include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../../..//modules/gitlab/group"
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  group_name   = "terraform"
  group_path   = "terraform"
  description  = "Terraform modules used in provisioning the Testing Farm infrastructure"
}
