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

resource "gitlab_group" "group" {
  name             = var.group_name
  path             = var.group_path
  description      = var.description
  visibility_level = "public"
  parent_id        = 5515434
}
