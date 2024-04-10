# Root level terragrunt configuration, skip processing it
# https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#skip
skip = true

# Create terraform cloud workspace
terraform {
  before_hook "before_hook" {
    commands = ["apply", "init", "import", "plan"]
    execute = [
      "terraform-cloud",
      "create-workspace", "--ignore-existing", "infra-${replace(path_relative_to_include(), "/", "-")}"
    ]
  }
}

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
      name = "infra-${replace(path_relative_to_include(), "/", "-")}"
    }
  }
}
EOF
}
