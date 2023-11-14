# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

# Generate provider configuration for all configured modules
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "infra"
    }
  }
}
EOF
}
