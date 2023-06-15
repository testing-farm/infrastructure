terraform {
  required_version = ">=1.0.9"
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "testing-farm"

    workspaces {
      name = "production"
    }
  }

  required_providers {
    external = {
      version = ">=2.2.0"
    }
    aws = {
      version = ">=4.0.0"
    }
  }
}

locals {
  cluster = {
    name = "testing-farm-production"

    vpc_id = "vpc-0896aedab4753e76f"

    subnet_ids = [
      "subnet-029d836119c84a77e",
      "subnet-03089904253762f32"
    ]
  }

  workers = {
    security_group = "sg-0040a2477d37dd6d0"
  }

  tags = {
    FedoraGroup  = "ci"
    ServiceOwner = "TFT"
    ServicePhase = "Prod"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  region = "us-east-2"
  alias  = "us-east-2"

  default_tags {
    tags = local.tags
  }
}

module "production-cluster" {
  source = "../../"

  cluster_default_region            = "us-east-1"
  cluster_vpc_id                    = local.cluster.vpc_id
  cluster_subnets                   = local.cluster.subnet_ids
  cluster_name                      = local.cluster.name
  cluster_node_group_instance_types = ["c5.2xlarge"]
  cluster_node_group_disk_size      = 500
  cluster_node_group_scaling = {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  ansible_vault_password_file = var.ansible_vault_password_file
  ansible_vault_credentials   = var.ansible_vault_credentials
  ansible_vault_secrets_root  = var.ansible_vault_secrets_root

  artemis_release_name = "artemis"
  artemis_namespace    = "default"
  artemis_image_tag    = "v0.0.57"

  artemis_additional_lb_source_ips = data.aws_instances.workers.public_ips

  artemis_config_root   = "./config"
  artemis_config_common = "../common/config"
  artemis_config_extra_files = [
    "ARTEMIS_HOOK_AWS_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_AZURE_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_BEAKER_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_OPENSTACK_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_ROUTE.py",
    "variables_images.yaml"
  ]
  artemis_config_extra_templates = [{
    source = "artemis-image-map-aws.yaml.tftpl"
    target = "artemis-image-map-aws.yaml"
    vars   = ["./config/variables_images.yaml"]
  }]
  artemis_ssh_keys = [{
    name  = "master-key"
    owner = "artemis"
    path  = "master-key.yaml"
    key   = ""
  }]

  artemis_api_processes = 4
  artemis_api_threads   = 2

  artemis_guest_security_group_id = aws_security_group.allow_guest_traffic.id

  artemis_worker_extra_env = [
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_x86_64",
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_aarch64",
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_x86_64",
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_aarch64",
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    }
  ]

  artemis_worker_replicas  = 5
  artemis_worker_processes = 4
  artemis_worker_threads   = 8

  resources = {
    artemis_api = {
      limits = {
        memory = "2Gi"
      }
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
    }

    artemis_dispatcher = {
      limits = {
        memory = "1Gi"
      }
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }

    artemis_initdb = {
      limits = {
        memory = "128Mi"
      }
      requests = {
        cpu    = "200m"
        memory = "128Mi"
      }
    }

    artemis_init_containers = {
      limits = {
        memory = "48Mi"
      }
      requests = {
        cpu    = "20m"
        memory = "48Mi"
      }
    }

    artemis_scheduler = {
      limits = {
        memory = "2Gi"
      }
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }

    artemis_worker = {
      limits = {
        memory = "6Gi"
      }
      requests = {
        cpu    = "150m"
        memory = "512Mi"
      }
    }

    rabbitmq = {
      limits = {
        memory = "4Gi"
      }
      requests = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }

    postgresql = {
      limits = {
        memory = "8Gi"
      }
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }

    postgresql_exporter = {
      limits = {
        memory = "32Mi"
      }
      requests = {
        cpu    = "20m"
        memory = "32Mi"
      }
    }

    redis = {
      limits = {
        memory = "256Mi"
      }
      requests = {
        cpu    = "100m"
        memory = "48Mi"
      }
    }

    redis_exporter = {
      limits = {
        memory = "32Mi"
      }
      requests = {
        cpu    = "20m"
        memory = "32Mi"
      }
    }
  }
}

data "aws_instances" "workers" {
  provider = aws.us-east-2

  filter {
    name   = "instance.group-id"
    values = [local.workers.security_group]
  }

  instance_state_names = ["running"]
}

resource "aws_security_group" "allow_guest_traffic" {
  name        = "${local.cluster.name}-allow-guest-traffic"
  description = "Security group for Artemis guests"
  vpc_id      = "vpc-a4f084cd"

  provider = aws.us-east-2

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = concat(
      module.production-cluster.artemis_lb_source_ranges,
      [for public_ip in data.aws_instances.workers.public_ips : "${public_ip}/32"]
    )
    description = "Allow SSH inbound traffic from workers and additional IPs"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    ipv6_cidr_blocks = ["::/0"]      #tfsec:ignore:aws-ec2-no-public-egress-sgr
    description      = "Allow all outbound traffic"
  }
}
