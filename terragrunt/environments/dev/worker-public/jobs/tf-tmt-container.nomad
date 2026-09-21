job "tf-tmt-container" {
  type        = "batch"
  datacenters = ["dc1"]

  parameterized {
    meta_required = ["REQUEST_ID"]
  }

  group "tmt" {

    # Restart up to 2 times
    restart {
      attempts = 2
    }

    reschedule {
      attempts = 2
    }

    # Containers can take a lot of space, especially if they download a lot of data
    # Set to 50GB now
    ephemeral_disk {
      size = "50000"
    }

    task "tmt" {
      driver = "podman"

      resources {
        cpu    = 2000
        memory = 8192
      }

      config {
        # TODO: revert to latest once merged
        image        = "quay.io/testing-farm/worker-public:68d72a1b"
        network_mode = "host"
        init         = true
        security_opt = ["label=disable"]

        volumes = [
          # Config bundle is extracted at runtime by /bin/tf-tmt-container
          # (extract_citool_config) into /etc/gluetool.d/config via the podma
          # Artemis private key: host-only secret, layered in at the config-bundle root
          # (${config_root}), so config/artemis's `ssh-key = ${config_root}/i
          "/etc/citool.d/id_rsa_artemis:/CONFIG_SECRETS/id_rsa_artemis:ro",
          # environment.yaml: gluetool eval_context vars, must sit at the bun
          "/etc/citool.d/environment.yaml:/CONFIG/environment.yaml:ro",
          # Secrets config dir: second --module-config-path entry (set_module
          # Kept OUT of /etc/gluetool.d so the config-image extraction can't collide with it.
          # Overrides the public config per-key (e.g. api-key in testing-farm
          "/etc/citool.d/config:/CONFIG-SECRETS/config:ro",
          "/var/ARTIFACTS:/var/ARTIFACTS",
          "{{ nomad_podman_socket_path }}:/run/podman/podman.sock",
          "{{ nomad_home_dir }}/.ssh/agent.sock:/run/ssh-agent.sock",
{% if nomad_user != "root" %}
          "{{ nomad_containers_conf_path }}:/etc/containers/containers.conf",
{% endif %}
        ]

        entrypoint = ["/bin/tf-tmt-container"]
      }

      env {
        CONTAINER_HOST = "unix:///run/podman/podman.sock"
        ARTIFACTS_DIR  = "/var/ARTIFACTS"
        SSH_AUTH_SOCK  = "/run/ssh-agent.sock"

        CITOOL_CONFIG_IMAGE_DEFAULT = "quay.io/testing-farm/ranch-public:latest"
      }

      kill_timeout = "15m"
    }
  }
}
