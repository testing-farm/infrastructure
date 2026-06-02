terraform {
  required_version = ">=1.2.0"
  required_providers {
    ansiblevault = {
      source  = "MeilleursAgents/ansiblevault"
      version = ">=2.2.0"
    }
    aws = {
      version = ">=4.0.0, <6.0.0"
    }
    helm = {
      version = ">=2.9.0, <3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">=2.18.1, <3.0.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">=3.2.3"
    }
  }
}

locals {
  kube_addons_namespace = "kube-addons"
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
    # Convert self-managed components to managed addons for automatic
    # version compatibility on EKS upgrades
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent    = true
      before_compute = var.addons_before_compute
    }
    vpc-cni = {
      most_recent    = true
      before_compute = var.addons_before_compute
    }
    # Enable kubectl top and HPA support
    eks-pod-identity-agent = {
      most_recent = true
    }
    metrics-server = {
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
    ami_type       = var.node_group_ami_type
    disk_size      = var.node_group_ami_type == "AL2_x86_64" ? var.node_group_disk_size : null
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

      # AL2 uses the Amazon-managed launch template where `disk_size` works.
      # AL2023 requires a custom launch template where `disk_size` is ignored,
      # so we specify the root volume via `block_device_mappings` instead.
      use_custom_launch_template = var.node_group_ami_type != "AL2_x86_64"
      block_device_mappings = var.node_group_ami_type != "AL2_x86_64" ? {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = var.node_group_disk_size
            volume_type = "gp3"
          }
        }
      } : {}

      # NOTE: IPv6 is disabled at the gitlab-runner level via `pre_build_script`
      # rather than here because the EKS module v19.x doesn't support custom
      # userdata with AL2023 (which uses `nodeadm` instead of `bootstrap.sh`).
      # Upgrading to EKS module v20.x would allow node-level IPv6 disable via
      # `cloudinit_pre_nodeadm` with `node.eks.aws` sysctl configuration.
    }
  }
}

data "aws_nat_gateway" "cluster" {
  count = var.nat_gateway ? 1 : 0

  vpc_id = var.vpc_id
  state  = "available"

  filter {
    name   = "tag:Name"
    values = ["${var.cluster_name}-eks"]
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

# Wait for the freshly created EKS API endpoint to become reachable before
# creating any Kubernetes/Helm resources. A newly created cluster can report
# `ACTIVE` before its public endpoint DNS has propagated to the runner's
# resolver, which then negative-caches the `NXDOMAIN`. That previously caused
# intermittent `dial tcp: lookup <endpoint>: no such host` failures on the
# `kubernetes_*` resources below, breaking the dev CI pipeline at random.
resource "null_resource" "wait_for_cluster_endpoint" {
  triggers = {
    cluster_endpoint = module.eks.cluster_endpoint
  }

  provisioner "local-exec" {
    command     = <<EOT
host="${trimprefix(module.eks.cluster_endpoint, "https://")}"
timeout=600
start_time=$(date +%s)
echo "Waiting for EKS API endpoint '$host' to become reachable..."
# A non-error HTTP response (e.g. 401) is success: it means DNS resolved and
# the control plane answered. We only gate on reachability, not on `--fail`.
until curl -ksS --max-time 5 "https://$host/livez" > /dev/null 2>&1; do
  echo "EKS API endpoint '$host' not reachable yet..."
  sleep 5
  current_time=$(date +%s)
  elapsed_time=$((current_time - start_time))
  if [ "$elapsed_time" -ge "$timeout" ]; then
    echo "Timeout reached while waiting for EKS API endpoint '$host'."
    exit 1
  fi
done
echo "EKS API endpoint '$host' is reachable."
EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "kubernetes_storage_class" "gp3" {
  depends_on = [null_resource.wait_for_cluster_endpoint]

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
}

resource "kubernetes_namespace" "kube-addons-ns" {
  depends_on = [null_resource.wait_for_cluster_endpoint]

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
  version    = "1.20.0"

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
  # Required since external-dns v0.15.1 migrated to aws-sdk-go-v2 which
  # needs an explicit region. Route 53 is global so any region works.
  - name: AWS_DEFAULT_REGION
    value: us-east-1
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
