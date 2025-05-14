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

resource "gitlab_project" "project" {
  name                                             = var.project_name
  description                                      = var.description
  namespace_id                                     = var.namespace_id
  visibility_level                                 = "public"
  default_branch                                   = var.default_branch
  approvals_before_merge                           = 2
  merge_method                                     = "ff"
  remove_source_branch_after_merge                 = true
  squash_option                                    = "default_on"
  only_allow_merge_if_pipeline_succeeds            = true
  only_allow_merge_if_all_discussions_are_resolved = true
  build_git_strategy                               = "fetch"
  initialize_with_readme                           = true
}

resource "gitlab_branch_protection" "default_branch_protection" {
  project                = gitlab_project.project.id
  branch                 = var.default_branch
  push_access_level      = "no one"
  merge_access_level     = "maintainer"
  unprotect_access_level = "maintainer"
}
