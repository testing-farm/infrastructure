terraform {
  required_version = ">=1.2.0"
  required_providers {
    ansiblevault = {
      source  = "MeilleursAgents/ansiblevault"
      version = ">=2.2.0"
    }
    aws = {
      version = ">=4.0.0"
    }
    helm = {
      version = ">=2.9.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.18.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.3"
    }
  }
}

locals {
  kube_addons_namespace = "kube-addons"
  asg_name              = module.eks.eks_managed_node_groups.default_node_group.node_group_autoscaling_group_names[0]
}

provider "ansiblevault" {
  vault_path  = var.ansible_vault_password_file
  root_folder = var.ansible_vault_secrets_root
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args = [
        "--profile",
        var.aws_profile,
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name
      ]
      command = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args = [
      "--profile",
      var.aws_profile,
      "eks",
      "get-token",
      "--cluster-name",
      var.cluster_name
    ]
    command = "aws"
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
  version = ">= v19.10.0, < v20.0.0"

  cluster_name    = var.cluster_name
  cluster_version = var.eks_version

  subnet_ids = var.subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
      configuration_values = jsonencode({
        controller = {
          # tags to apply for each created EBS volume
          # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/tagging.md
          extraVolumeTags = var.resource_tags
          # support volume modifications via PVC annotations
          # https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/modify-volume.md
          volumeModificationFeature = {
            enabled = true
          }
        }
      })
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

data "ansiblevault_path" "pool_access_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.profiles.fedora_us_east_2.access_key"
}

data "ansiblevault_path" "pool_secret_key_aws" {
  path = var.ansible_vault_credentials
  key  = "credentials.aws.profiles.fedora_us_east_2.secret_key"
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

resource "kubernetes_namespace" "kube-addons-ns" {
  metadata {
    name = local.kube_addons_namespace
  }
}

resource "kubernetes_secret" "aws-credentials-secret" {
  depends_on = [kubernetes_namespace.kube-addons-ns]

  metadata {
    name      = "aws-credentials"
    namespace = local.kube_addons_namespace
  }

  data = {
    "credentials" = <<EOF
[default]
aws_access_key_id = ${sensitive(data.ansiblevault_path.pool_access_key_aws.value)}
aws_secret_access_key = ${sensitive(data.ansiblevault_path.pool_secret_key_aws.value)}
EOF
  }
}

resource "helm_release" "external-dns" {
  depends_on = [
    kubernetes_namespace.kube-addons-ns,
    kubernetes_secret.aws-credentials-secret
  ]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.11.0"

  namespace = local.kube_addons_namespace

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "txtOwnerId"
    value = var.cluster_name
  }

  set {
    name  = "domainFilters"
    value = "{${var.route53_zone}}"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  values = [
    <<EOF
env:
  - name: AWS_SHARED_CREDENTIALS_FILE
    value: /.aws/credentials
extraVolumes:
  - name: aws-credentials
    secret:
      secretName: aws-credentials
extraVolumeMounts:
  - name: aws-credentials
    mountPath: /.aws
    readOnly: true
EOF
  ]

  set {
    name  = "extraArgs"
    value = "{--aws-zone-type=public}"
  }
}

# ASGs created by EKS do not inherit tags, need to set them separately and refresh the instances to get the new tags
# https://github.com/aws/containers-roadmap/issues/608
# https://github.com/terraform-aws-modules/terraform-aws-eks/issues/860
resource "null_resource" "add_custom_tags_to_asg" {
  triggers = {
    node_group = local.asg_name
    tags       = jsonencode(var.resource_tags)
  }

  provisioner "local-exec" {
    command = <<EOF
aws --profile ${var.aws_profile} autoscaling create-or-update-tags \
    --tags $(echo '${jsonencode([for key, value in var.resource_tags : { Key = key, Value = value, PropagateAtLaunch = true, ResourceId = local.asg_name, ResourceType = "auto-scaling-group" }])}' | jq -c '.[]') && \
aws --profile ${var.aws_profile} autoscaling start-instance-refresh --auto-scaling-group-name ${local.asg_name}
EOF
  }
}
