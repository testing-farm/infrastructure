variable "name" {
  description = "Name of the artifact server instance"
  type        = string
}

variable "ami_name" {
  description = "AMI name pattern selecting the newest available artifact-server release"
  type        = string
}

variable "ami_name_regex" {
  description = "Anchored release-only AMI name expression, excluding MR and diagnostic uploads"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "EC2 key-pair name for administrator SSH access"
  type        = string
}

variable "subnet_id" {
  description = "Subnet containing the S3 Files mount target"
  type        = string
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IPv4 address with the instance"
  type        = bool
}

variable "enable_volume_tags" {
  description = "Whether the EC2 module tags the instance's volumes"
  type        = bool
}

variable "iam_instance_profile" {
  description = "Instance profile supplied by the storage deployment"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "Frontend and NFS client security groups"
  type        = list(string)
}

variable "root_block_device" {
  description = "Root volume configuration"
  type = list(object({
    encrypted   = bool
    volume_type = string
    volume_size = number
  }))
}

variable "metadata_options" {
  description = "Instance metadata service configuration"
  type = object({
    http_endpoint = string
    http_tokens   = string
  })
}
