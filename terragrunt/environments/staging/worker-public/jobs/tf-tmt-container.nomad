job "tf-tmt-container" {
  type        = "batch"
  datacenters = ["dc1"]

  parameterized {
      meta_required = ["REQUEST_ID"]
      meta_optional = ["CITOOL_IMAGE", "CITOOL_CONFIG_IMAGE", "REQUEST_TIMEOUT"]
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
      driver = "raw_exec"

      # The job script stops the citool container and removes the tmt containers and networks on
      # the host podman when it gets the signal. 30s is the default `max_kill_timeout` of the client.
      kill_signal  = "SIGTERM"
      kill_timeout = "30s"

      resources {
        cpu    = 2000
        memory = 8192
      }

      config {
        command = "tf-tmt-container"
        args = ["${NOMAD_META_REQUEST_ID}", "${NOMAD_ALLOC_DIR}"]
      }
    }
  }
}
