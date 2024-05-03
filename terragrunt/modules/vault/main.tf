terraform {
  required_version = ">=1.2.0"

  required_providers {
    ansible = {
      version = "~> 1.2.0"
      source  = "ansible/ansible"
    }
  }
}

resource "ansible_vault" "secrets" {
  vault_file          = var.vault_file
  vault_password_file = var.vault_password_file
}
