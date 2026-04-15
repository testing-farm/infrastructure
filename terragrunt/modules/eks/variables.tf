variable "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
  type        = string
}

variable "aws_profile" {
  description = "Name of AWS profile."
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

variable "node_group_ami_type" {
  description = "AMI type for EKS managed node group. Use AL2023_x86_64_STANDARD for cgroupsv2 support."
  type        = string
  default     = "AL2_x86_64"
}

variable "nat_gateway" {
  description = "Whether the cluster uses a NAT gateway for stable egress. When true, looks up the NAT gateway EIP via the Name tag."
  type        = bool
  default     = false
}

variable "addons_before_compute" {
  # TODO: enable by default once staging/production addon state is migrated
  # via `terraform state mv 'module.eks.aws_eks_addon.this["vpc-cni"]' 'module.eks.aws_eks_addon.before_compute["vpc-cni"]'`
  # and same for kube-proxy.
  description = "Install vpc-cni and kube-proxy before node groups. Enable for new clusters to prevent CNI race conditions. Disable for existing clusters to avoid addon state migration."
  type        = bool
  default     = false
}
