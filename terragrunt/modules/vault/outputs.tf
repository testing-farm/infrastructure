output "secrets" {
  value     = yamldecode(ansible_vault.secrets.yaml)
  sensitive = true
}
