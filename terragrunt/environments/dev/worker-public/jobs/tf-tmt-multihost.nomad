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

    # The worker container sees the allocation directory as /var/ARTIFACTS/<request-id>.
    # tmt hands that path to the host podman as a volume source, so the same path must
    # exist on the host too. Link it there for the lifetime of the allocation.
    task "artifacts-link" {
      lifecycle {
        hook = "prestart"
      }

      driver = "raw_exec"

      config {
        command = "/usr/bin/ln"
        args    = ["-sfn", "${NOMAD_ALLOC_DIR}", "/var/ARTIFACTS/${NOMAD_META_REQUEST_ID}"]
      }

      resources {
        cpu    = 50
        memory = 32
      }
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
        security_opt = ["label=type:tf_worker.process"]

        volumes = [
          "/etc/citool.d:/etc/gluetool.d:O",
          # Each request writes only to its own allocation directory, see the "artifacts-link" task
          "{{ nomad_data_dir }}/alloc/${NOMAD_ALLOC_ID}/alloc:/var/ARTIFACTS/${NOMAD_META_REQUEST_ID}:z",
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

    task "artifacts-unlink" {
      lifecycle {
        hook = "poststop"
      }

      driver = "raw_exec"

      config {
        command = "/usr/bin/rm"
        args    = ["-f", "/var/ARTIFACTS/${NOMAD_META_REQUEST_ID}"]
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
