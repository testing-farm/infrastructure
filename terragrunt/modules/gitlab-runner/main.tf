terraform {
  required_version = ">=1.2.0"

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = ">=16.5.0"
    }
    helm = {
      version = ">=2.9.0, <3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.18.1, <3.0.0"
    }
  }
}

# Create runner configuration in GitLab
resource "gitlab_user_runner" "runner" {
  runner_type = "group_type"
  group_id    = var.gitlab_group_id
  description = var.runner_description
  tag_list    = var.runner_tags
  untagged    = var.run_untagged
}

# Create a dedicated namespace for the runner
resource "kubernetes_namespace" "gitlab_runner" {
  metadata {
    name = var.namespace
  }
}

# Deploy GitLab Runner via Helm
resource "helm_release" "gitlab_runner" {
  depends_on = [kubernetes_namespace.gitlab_runner]

  name       = var.release_name
  repository = "https://charts.gitlab.io"
  chart      = "gitlab-runner"
  version    = var.chart_version
  namespace  = var.namespace

  atomic        = true
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  set {
    name  = "gitlabUrl"
    value = var.gitlab_url
  }

  set_sensitive {
    name  = "runnerToken"
    value = gitlab_user_runner.runner.token
  }

  set {
    name  = "rbac.create"
    value = "true"
  }

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      concurrent     = var.concurrent
      check_interval = var.check_interval
    })
  ]
}
