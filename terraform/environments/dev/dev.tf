terraform {
  required_version = ">=1.0.9"
  backend "local" {}

  required_providers {
    external = {
      version = ">=2.2.0"
    }
    aws = {
      version = ">=4.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

data "external" "localhost_public_ip" {
  # Public IP of localhost, used for development Artemis IP access whitelist
  program = [
    "sh",
    "-c",
    "jq -n --arg output \"$(curl -s icanhazip.com)\" '{$output}'"
  ]
}

module "devel-cluster" {
  source = "../../"

  # TODO: move to staging subnets once working
  cluster_default_region            = "us-east-2"
  cluster_vpc_id                    = "vpc-0f6baa3d6bae8d912"
  cluster_subnets                   = ["subnet-010f90da92f36876e", "subnet-0a704a759f7671044"]
  cluster_name                      = var.cluster_name
  cluster_node_group_instance_types = ["c5.2xlarge"]
  cluster_node_group_disk_size      = 500
  cluster_node_group_scaling = {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  ansible_vault_password_file = var.ansible_vault_password_file
  ansible_vault_credentials   = var.ansible_vault_credentials
  ansible_vault_secrets_root  = var.ansible_vault_secrets_root

  artemis_release_name = "artemis"
  artemis_namespace    = "default"

  artemis_additional_lb_source_ips = [data.external.localhost_public_ip.result.output]

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

  artemis_api_processes = 2
  artemis_api_threads   = 1

  artemis_guest_security_group_id = aws_security_group.allow_guest_traffic.id

  artemis_worker_extra_env = [
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_x86_64",
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_aarch64",
      value = "/configuration/artemis-image-map-aws.yaml"
    }
  ]
  artemis_worker_replicas  = 1
  artemis_worker_processes = 2
  artemis_worker_threads   = 1

  resources = {
    artemis_api = {
      limits = {
        memory = "512Mi"
      }
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
    }

    artemis_dispatcher = {
      limits = {
        memory = "128Mi"
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
        memory = "128Mi"
      }
      requests = {
        cpu    = "50m"
        memory = "128Mi"
      }
    }

    artemis_worker = {
      limits = {
        memory = "512Mi"
      }
      requests = {
        cpu    = "150m"
        memory = "512Mi"
      }
    }

    rabbitmq = {
      limits = {
        memory = "512Mi"
      }
      requests = {
        cpu    = "200m"
        memory = "256Mi"
      }
    }

    postgresql = {
      limits = {
        memory = "256Mi"
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
        memory = "48Mi"
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

resource "aws_security_group" "allow_guest_traffic" {
  name        = "${var.cluster_name}-allow-guest-traffic"
  description = "Allow traffic for development from localhost"
  vpc_id      = "vpc-a4f084cd"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.external.localhost_public_ip.result.output}/32"]
    description = "Allow SSH inbound traffic"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    ipv6_cidr_blocks = ["::/0"]      #tfsec:ignore:aws-ec2-no-public-egress-sgr
    description      = "Allow all outbound traffic"
  }

  tags = {
    FedoraGroup = "ci"
  }
}
