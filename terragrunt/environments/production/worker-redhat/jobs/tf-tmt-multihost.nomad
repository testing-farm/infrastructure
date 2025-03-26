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
      driver = "raw_exec"

      resources {
        cpu    = 500
        memory = 3072
      }

      config {
        command = "tf-tmt-multihost"
        args = ["${NOMAD_META_REQUEST_ID}", "${NOMAD_ALLOC_DIR}", "12h", "3072m"]
      }
    }
  }
}
