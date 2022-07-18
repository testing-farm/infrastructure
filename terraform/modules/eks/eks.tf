module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  subnet_ids = var.cluster_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  create_iam_role = false
  iam_role_arn    = var.cluster_role_arn

  create_cloudwatch_log_group = false
  enable_irsa                 = false

  tags = var.resource_tags

  vpc_id = var.vpc_id

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = "${var.node_group_disk_size}"
    instance_types = "${var.node_group_instance_types}"
  }

  eks_managed_node_groups = {
    default_node_group = {
      create_iam_role = false
      iam_role_arn    = "${var.node_group_role_arn}"

      tags = "${var.resource_tags}"

      # NOTE: this will make sure we use the Amazon provided lunch templates
      create_launch_template = false
      launch_template_name   = ""
    }
  }
}

data "aws_route53_zone" "testing_farm_zone" {
  name = "testing-farm.io"
}

resource "aws_route53_record" "eks-friendly-endpoint" {
  zone_id = data.aws_route53_zone.testing_farm_zone.zone_id
  name    = "https://api.${module.eks.cluster_id}.eks.${data.aws_route53_zone.testing_farm_zone.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [trimprefix(module.eks.cluster_endpoint, "https://")]
}

resource "aws_ec2_tag" "subnet_tag" {
   count       = length(var.cluster_subnets)

   resource_id = var.cluster_subnets[count.index]
   key         = "kubernetes.io/cluster/${module.eks.cluster_id}"
   value       = "shared"
 }
