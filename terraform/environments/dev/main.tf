terraform {
  backend "local" {}
}

module "testing-farm-eks-devel" {
    source = "../../modules/eks/"

    # NOTE: cluster_name is set by direnv
    cluster_name = "${var.cluster_name}"

    # TODO: move to staging subnets once working
    aws_default_region = "us-east-2"
    vpc_id = "vpc-0f6baa3d6bae8d912"

    cluster_subnets = ["subnet-010f90da92f36876e", "subnet-0a704a759f7671044"]
    cluster_version = "1.21"
}
