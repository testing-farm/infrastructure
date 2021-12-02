variable cluster_name {
    description = "EKS cluster name to create."
}

variable cluster_role_arn {
    description = "ARN of the IAM role that provides permissions for the Kubernetes control plane to make calls to AWS API operations on your behalf."
    default = "arn:aws:iam::125523088429:role/fedora-ci-eks"
}

variable cluster_subnets {
    description = "List of subnet IDs. Must be in at least two different availability zones."
    type = list(string)
}

variable aws_default_region {
    description = "AWS default region."
}
