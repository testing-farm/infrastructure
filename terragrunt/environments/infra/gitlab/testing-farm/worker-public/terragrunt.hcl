generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "gitlab-testing-farm-worker-public"
    }
  }
}
EOF
}

terraform {
  source = "../../../../..//modules/gitlab/project"
}

inputs = {
  gitlab_token = get_env("TF_VAR_gitlab_testing_farm_bot")
  project_name   = "worker-public"
}
