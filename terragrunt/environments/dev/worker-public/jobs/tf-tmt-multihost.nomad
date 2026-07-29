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
        image        = "quay.io/testing-farm/worker-public:03abae02"
        privileged   = true
        network_mode = "host"
        init         = true
        security_opt = ["label=disable"]

        volumes = [
          "/etc/citool.d:/etc/gluetool.d:O",
          "/var/ARTIFACTS:/var/ARTIFACTS:z",
          "/run/podman/podman.sock:/run/podman/podman.sock",
          "/root/.ssh:/root/.ssh:ro",
        ]

        entrypoint = ["/bin/tf-tmt-multihost"]
      }

      env {
        CONTAINER_HOST = "unix:///run/podman/podman.sock"
        ARTIFACTS_DIR  = "/var/ARTIFACTS"
      }

      kill_timeout = "15m"
    }
  }
}
