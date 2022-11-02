terraform {
  backend "local" {}
}

module "devel-cluster" {
  source = "../../"

  # TODO: move to staging subnets once working
  cluster_default_region = "us-east-2"
  cluster_vpc_id         = "vpc-0f6baa3d6bae8d912"
  cluster_subnets        = ["subnet-010f90da92f36876e", "subnet-0a704a759f7671044"]
  cluster_name           = var.cluster_name

  ansible_vault_password_file = var.ansible_vault_password_file
  ansible_vault_credentials   = var.ansible_vault_credentials
  ansible_vault_secrets_root  = var.ansible_vault_secrets_root

  artemis_release_name = "artemis"
  artemis_namespace    = "default"

  artemis_config_root   = "./config"
  artemis_config_common = "../common/config"
  artemis_config_extra_files = [
    "ARTEMIS_HOOK_AWS_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_AZURE_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_BEAKER_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_OPENSTACK_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_ROUTE.py",
    "variables_images.yml"
  ]
  artemis_config_extra_templates = [{
    source = "artemis-image-map-aws.yml.tftpl"
    target = "artemis-image-map-aws.yml"
    vars   = ["./config/variables_images.yml"]
  }]
  artemis_ssh_keys = [{
    name  = "master-key"
    owner = "artemis"
    path  = "master-key.yml"
    key   = ""
  }]

  artemis_api_processes = 2
  artemis_api_threads   = 1

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
