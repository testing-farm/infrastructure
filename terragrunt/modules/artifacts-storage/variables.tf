variable "bucket_name" {
  description = "Name of the S3 bucket for artifact storage"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the mount target and security groups reside"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the S3 Files mount target"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for naming AWS resources"
  type        = string
}
