variable cluster_name {
    description = "EKS cluster name to create."
}

variable cluster_subnets {
    description = "List of subnet IDs. Must be in at least two different availability zones."
    type = list(string)
    # VPC: fedora-ci-eks-stg
    # https://us-east-2.console.aws.amazon.com/vpc/home?region=us-east-2#subnets:VpcId=vpc-0618f77c2f99c9956
    default = ["subnet-0b94535bacb5965af", "subnet-0545e3522c521a064"]
}

variable aws_default_region {
    description = "AWS default region for the development environment."
    default = "us-east-2"
}
