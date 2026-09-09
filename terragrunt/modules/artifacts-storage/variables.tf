variable "bucket_name" {
  description = "Name of the S3 bucket for artifact storage"
  type        = string
  default     = "testing-farm-artifacts-redhat"
}

variable "vpc_id" {
  description = "VPC ID where the mount target and security groups reside"
  type        = string
  default     = "vpc-008152fcfb0333f30"
}

variable "subnet_id" {
  description = "Subnet ID for the S3 Files mount target"
  type        = string
  default     = "subnet-036ad213c3fb0eb7e"
}

variable "name_prefix" {
  description = "Prefix for naming AWS resources"
  type        = string
  default     = "testing-farm-artifacts-redhat"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
