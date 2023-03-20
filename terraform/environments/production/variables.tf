variable "cluster_name" {
  type    = string
  default = "testing-farm-production"
}                                         # tflint-ignore: terraform_typed_variables
variable "ansible_vault_password_file" {} # tflint-ignore: terraform_typed_variables
variable "ansible_vault_credentials" {}   # tflint-ignore: terraform_typed_variables
variable "ansible_vault_secrets_root" {}  # tflint-ignore: terraform_typed_variables
