output "namespace" {
  description = "Kubernetes namespace where the runner is deployed."
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.gitlab_runner.name
}

output "runner_id" {
  description = "GitLab runner ID."
  value       = gitlab_user_runner.runner.id
}
