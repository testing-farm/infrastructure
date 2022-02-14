variable "aws_default_region" {
  description = "AWS default region."
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
}

variable "cluster_name" {
  description = "EKS cluster name to create."
}

variable "cluster_version" {
  description = "EKS cluster version."
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role that provides permissions for the Kubernetes control plane to make calls to AWS APIs on your behalf."
  default     = "arn:aws:iam::125523088429:role/fedora-ci-eks"
}

variable "node_group_role_arn" {
  description = "ARN of the IAM role that provides permissions for the Kubernetes node kubelet to make calls to AWS APIs on your behalf."
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

variable "resource_tags" {
  description = "An dictionary of tags applied to cluster and nodes."
  type        = map
  default = {
    FedoraGroup = "ci"
  }
}

variable "cluster_subnets" {
  description = "List of subnet IDs. Must be in at least two different availability zones."
  type        = list(string)
}
