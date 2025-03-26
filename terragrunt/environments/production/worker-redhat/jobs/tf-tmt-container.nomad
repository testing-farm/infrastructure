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
    ephemeral_disk {
      size = "250000"
    }

    task "tmt" {
      driver = "raw_exec"

      resources {
        cpu    = 2000
        memory = 8192
      }

      config {
        command = "tf-tmt-container"
        args = ["${NOMAD_META_REQUEST_ID}", "${NOMAD_ALLOC_DIR}", "12h", "3072m"]
      }
    }
  }
}
