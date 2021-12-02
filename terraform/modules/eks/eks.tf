resource "aws_eks_cluster" "testing_farm" {
  name     = "${var.cluster_name}"
  role_arn = "${var.cluster_role_arn}"

  vpc_config {
    subnet_ids = "${var.cluster_subnets}"
  }
}

output "eks-endpoint" {
  value = aws_eks_cluster.testing_farm.endpoint
}

output "eks-cluster-name" {
  value = aws_eks_cluster.testing_farm.name
}
