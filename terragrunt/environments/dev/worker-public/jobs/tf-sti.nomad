job "tf-sti" {
  type        = "batch"
  datacenters = ["dc1"]

  parameterized {
      meta_required = ["REQUEST_ID"]
  }

  group "sti" {

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

    task "sti" {
      driver = "raw_exec"

      resources {
        cpu    = 500
        memory = 3072
      }

      config {
        command = "tf-sti"
        args = ["${NOMAD_META_REQUEST_ID}", "${NOMAD_ALLOC_DIR}"]
      }
    }
  }
}
