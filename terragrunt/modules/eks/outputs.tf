output "cluster" {
  value     = module.eks
  sensitive = true
}

output "nat_gateway_eip" {
  description = "NAT gateway Elastic IP for stable egress."
  value       = var.nat_gateway ? data.aws_nat_gateway.cluster[0].public_ip : ""
}

output "vpc_id" {
  description = "VPC ID where the EKS cluster is deployed"
  value       = var.vpc_id
}
