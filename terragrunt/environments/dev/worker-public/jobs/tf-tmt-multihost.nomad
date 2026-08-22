job "tf-tmt-multihost" {
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

    ephemeral_disk {
      size = "5000"
    }

    task "tmt" {
      driver = "podman"

      resources {
        cpu    = 500
        memory = 3072
      }

      config {
        image        = "quay.io/testing-farm/worker-public:latest"
        network_mode = "host"
        init         = true
        security_opt = ["label=disable"]

        volumes = [
          "/etc/citool.d:/etc/gluetool.d:O",
          "/var/ARTIFACTS:/var/ARTIFACTS",
          "{{ nomad_podman_socket_path }}:/run/podman/podman.sock",
          "{{ nomad_home_dir }}/.ssh/agent.sock:/run/ssh-agent.sock",
{% if nomad_user != "root" %}
          "{{ nomad_containers_conf_path }}:/etc/containers/containers.conf",
{% endif %}
        ]

        entrypoint = ["/bin/tf-tmt-multihost"]
      }

      env {
        CONTAINER_HOST = "unix:///run/podman/podman.sock"
        ARTIFACTS_DIR  = "/var/ARTIFACTS"
        SSH_AUTH_SOCK  = "/run/ssh-agent.sock"
      }

      kill_timeout = "15m"
    }
  }
}
