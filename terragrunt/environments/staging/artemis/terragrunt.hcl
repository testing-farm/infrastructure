# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

# Read parent configuration
locals {
  common        = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  route53_zone  = local.common.inputs.route53_zone
  namespace     = get_env("TF_VAR_artemis_namespace", "default")
  domain_suffix = local.namespace == "default" ? "" : "-${local.namespace}"
}

# Use eks module from this repository
# More info: https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/
# NOTE: we might want to later put these in a separete repository
# NOTE: double slash, i.e. '//' is expected, see the above docs
terraform {
  source = "../../../modules//artemis"
}

dependency "eks" {
  config_path = "../eks"

  # https://terragrunt.gruntwork.io/docs/features/execute-terraform-commands-on-multiple-modules-at-once/#unapplied-dependency-and-mock-outputs
  mock_outputs = {
    cluster = {
      cluster_name     = "mock-cluster-name"
      cluster_endpoint = "mock-cluster-endpoint"
      ## this is not a secret, just mocked output
      cluster_certificate_authority_data = "bW9jay1jbHVzdGVyLWNlcnRpZmljYXRlCg==" # pragma: allowlist secret
    }
  }
}

inputs = {
  cluster_name                       = dependency.eks.outputs.cluster.cluster_name
  cluster_endpoint                   = dependency.eks.outputs.cluster.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster.cluster_certificate_authority_data
  cluster_aws_region                 = local.common.inputs.aws_region
  guests_aws_region                  = local.common.inputs.aws_region_guests

  # Strip `testing-farm-` from the cluster name as use that to construct the artemis API domain name.
  # For example for `testing-farm-production` cluster that would be `artemis.production.testing-farm.io`
  api_domain = "artemis.${trimprefix(dependency.eks.outputs.cluster.cluster_name, "testing-farm-")}${local.domain_suffix}.${local.common.inputs.route53_zone}"

  # Add localhost access to artemis and guests
  localhost_access = true

  release_name = "artemis"
  namespace    = local.namespace
  image_tag    = "v0.0.69"

  # Testing Farm worker tags used to identify workers for this environment
  testing_farm_worker_tags = {
    "FedoraGroup"      = "ci"
    "ServiceOwner"     = "TFT"
    "ServiceName"      = "TestingFarm"
    "ServiceComponent" = "Worker"
    "ServicePhase"     = "Stage"
  }

  ansible_vault_password_file = get_env("TF_VAR_ansible_vault_password_file")
  ansible_vault_credentials   = get_env("TF_VAR_ansible_vault_credentials")
  ansible_vault_secrets_root  = get_env("TF_VAR_ansible_vault_secrets_root")

  config_root = "${get_original_terragrunt_dir()}/config"
  config_extra_files = [
    "ARTEMIS_HOOK_AWS_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_AZURE_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_BEAKER_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_OPENSTACK_ENVIRONMENT_TO_IMAGE.py",
    "ARTEMIS_HOOK_ROUTE.py",
    "variables_images.yaml"
  ]

  config_extra_templates = [{
    source = "artemis-image-map-aws.yaml.tftpl"
    target = "artemis-image-map-aws.yaml"
    vars   = ["${get_original_terragrunt_dir()}/config/variables_images.yaml"]
  }]

  ssh_keys = [{
    name  = "master-key"
    owner = "artemis"
    path  = "master-key.yaml"
    key   = ""
  }]

  api_processes = 2
  api_threads   = 1

  worker_extra_env = [
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_x86_64",
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_aarch64",
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_x86_64_metal",  # pragma: allowlist secret
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_FILEPATH_fedora_aws_aarch64_metal",  # pragma: allowlist secret
      value = "/configuration/artemis-image-map-aws.yaml"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_x86_64",
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_aarch64",
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_x86_64_metal",  # pragma: allowlist secret
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    },
    {
      name  = "ARTEMIS_AWS_ENVIRONMENT_TO_IMAGE_MAPPING_NEEDLE_fedora_aws_aarch64_metal",  # pragma: allowlist secret
      value = "{{\"{{\"}} os.compose {{\"}}\"}}:{{\"{{\"}} hw.arch {{\"}}\"}}"
    }
  ]

  worker_replicas  = 2
  worker_processes = 2
  worker_threads   = 2

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
