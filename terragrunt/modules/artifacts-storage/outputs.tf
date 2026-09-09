output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.artifacts.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.artifacts.arn
}

output "file_system_id" {
  description = "ID of the S3 Files filesystem"
  value       = aws_s3files_file_system.artifacts.id
}

output "file_system_arn" {
  description = "ARN of the S3 Files filesystem"
  value       = aws_s3files_file_system.artifacts.arn
}

output "mount_target_id" {
  description = "ID of the S3 Files mount target"
  value       = aws_s3files_mount_target.artifacts.id
}

output "mount_target_ipv4_address" {
  description = "Private IPv4 address of the S3 Files mount target"
  value       = aws_s3files_mount_target.artifacts.ipv4_address
}

output "client_security_group_id" {
  description = "Security group ID for the NFS client (attached to EC2 instance)"
  value       = aws_security_group.nfs_client.id
}

output "mount_target_security_group_id" {
  description = "Security group ID for the S3 Files mount target"
  value       = aws_security_group.mount_target.id
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for the EC2 server"
  value       = aws_iam_instance_profile.ec2_client.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for the EC2 server"
  value       = aws_iam_instance_profile.ec2_client.arn
}

output "instance_role_arn" {
  description = "ARN of the IAM role for the EC2 server"
  value       = aws_iam_role.ec2_client.arn
}

output "service_role_arn" {
  description = "ARN of the IAM service role for S3 Files"
  value       = aws_iam_role.s3files_service.arn
}

output "subnet_id" {
  description = "Subnet ID of the mount target"
  value       = var.subnet_id
}

output "vpc_id" {
  description = "VPC ID where the mount target resides"
  value       = var.vpc_id
}

output "availability_zone" {
  description = "Availability Zone of the mount target subnet"
  value       = data.aws_subnet.selected.availability_zone
}

output "availability_zone_id" {
  description = "Availability Zone ID of the mount target subnet"
  value       = data.aws_subnet.selected.availability_zone_id
}
