variable "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
  type        = string
}

variable "aws_region" {
  description = "Name of AWS region"
  type        = string
}

variable "ansible_vault_password_file" {
  description = "Path to ansible vault password file."
  type        = string
}

variable "ansible_vault_credentials" {
  description = "Path to ansible vault-encrypted credentials."
  type        = string
}

variable "ansible_vault_secrets_root" {
  description = "Path to the root directory with ansible vault secrets."
  type        = string
}

variable "route53_zone" {
  description = "Name of AWS Route53 zone for DNS management"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name to create."
  type        = string
}

variable "eks_version" {
  description = "EKS cluster version."
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role that provides permissions for the Kubernetes control plane to make calls to AWS APIs on your behalf."
  type        = string
  default     = "arn:aws:iam::125523088429:role/fedora-ci-eks"
}

variable "node_group_role_arn" {
  description = "ARN of the IAM role that provides permissions for the Kubernetes node kubelet to make calls to AWS APIs on your behalf."
  type        = string
  default     = "arn:aws:iam::125523088429:role/aws-fedora-ci"
}

variable "node_group_instance_types" {
  description = "AWS EC2 instance types in the eks manager node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_disk_size" {
  description = "AWS EC2 instance root disk size."
  type        = number
  default     = 50
}

variable "node_group_scaling" {
  description = "AWS EC2 nodes scaling."
  type = object({
    desired_size = number
    min_size     = number
    max_size     = number
  })
  default = {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }
}

variable "resource_tags" {
  description = "An dictionary of tags applied to cluster and nodes."
  type        = map(any)
  default = {
    FedoraGroup = "ci"
  }
}

variable "subnets" {
  description = "List of subnet IDs. Must be in at least two different availability zones."
  type        = list(string)
}
