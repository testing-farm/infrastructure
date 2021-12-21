resource "aws_eks_cluster" "testing_farm" {
  name     = "${var.cluster_name}"
  role_arn = "${var.cluster_role_arn}"

  vpc_config {
    subnet_ids = "${var.cluster_subnets}"
  }
}

data "aws_route53_zone" "testing_farm_zone" {
  name         = "testing-farm.io"
}

resource "aws_route53_record" "eks-friendly-endpoint" {
  zone_id = data.aws_route53_zone.testing_farm_zone.zone_id
  name    = "https://api.${var.cluster_name}.eks.${data.aws_route53_zone.testing_farm_zone.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [trimprefix(aws_eks_cluster.testing_farm.endpoint, "https://")]
}

output "eks-endpoint" {
  value = aws_eks_cluster.testing_farm.endpoint
}

output "eks-friendly-endpoint" {
  value = aws_route53_record.eks-friendly-endpoint.name
}

output "eks-cluster-name" {
  value = aws_eks_cluster.testing_farm.name
}
