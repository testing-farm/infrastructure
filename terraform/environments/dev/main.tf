terraform {
  backend "local" {}
}

module "testing-farm-eks" {
    source = "../../modules/eks/"
    cluster_name = var.cluster_name
    aws_default_region = var.aws_default_region
    cluster_subnets = var.cluster_subnets
}
