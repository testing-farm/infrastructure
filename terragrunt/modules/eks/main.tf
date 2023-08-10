terraform {
  required_version = ">=1.2.0"
  required_providers {
    aws = {
      version = ">=4.0.0"
    }
  }
}

# Ignore these checks while we want to have public access to the cluster enabled
# tfsec:ignore:aws-eks-no-public-cluster-access
# tfsec:ignore:aws-eks-no-public-cluster-access-to-cidr
# tfsec:ignore:aws-ec2-no-public-egress-sgr  # HTTPS egress from nodes (should be tightened to port 443)
# tfsec:ignore:aws-eks-enable-control-plane-logging  # TODO logging and metrics
# tfsec:ignore:aws-eks-encrypt-secrets  # Missing permission to create encryption keys
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">=v19.10.0"

  cluster_name    = var.cluster_name
  cluster_version = var.eks_version

  subnet_ids = var.subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # We do not have the permission to create KMS keys
  create_kms_key            = false
  cluster_encryption_config = []

  create_iam_role = false
  iam_role_arn    = var.role_arn

  create_cloudwatch_log_group = false
  enable_irsa                 = false

  tags = var.resource_tags

  vpc_id = var.vpc_id

  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    disk_size      = var.node_group_disk_size
    instance_types = var.node_group_instance_types
    desired_size   = var.node_group_scaling.desired_size
    max_size       = var.node_group_scaling.max_size
    min_size       = var.node_group_scaling.min_size
  }

  eks_managed_node_groups = {
    default_node_group = {
      create_iam_role = false
      iam_role_arn    = var.node_group_role_arn

      tags = var.resource_tags

      # NOTE: this will make sure we use the Amazon provided lunch templates
      use_custom_launch_template = false
    }
  }
}

data "aws_route53_zone" "testing_farm_zone" {
  name = var.route53_zone
}

resource "aws_route53_record" "eks-friendly-endpoint" {
  zone_id = data.aws_route53_zone.testing_farm_zone.zone_id
  name    = "api.${module.eks.cluster_name}.eks.${data.aws_route53_zone.testing_farm_zone.name}"
  type    = "CNAME"
  ttl     = "300"
  records = [trimprefix(module.eks.cluster_endpoint, "https://")]
}

resource "aws_ec2_tag" "subnet_tag" {
  count = length(var.subnets)

  resource_id = var.subnets[count.index]
  key         = "kubernetes.io/cluster/${module.eks.cluster_name}"
  value       = "shared"
}
