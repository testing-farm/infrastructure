output "cluster" {
  value     = module.eks
  sensitive = true
}

output "vpc_id" {
  description = "VPC ID where the EKS cluster is deployed"
  value       = var.vpc_id
}
