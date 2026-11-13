job "tf-sti" {
  type        = "batch"
  datacenters = ["dc1"]

  parameterized {
    meta_required = ["REQUEST_ID"]
    meta_optional = ["CITOOL_IMAGE", "CITOOL_CONFIG_IMAGE", "REQUEST_TIMEOUT"]
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

    task "sti" {
      driver = "podman"

      resources {
        cpu    = 500
        memory = 3072
      }

      config {
        image        = "{{ citool_container_image }}"
        force_pull   = true
        network_mode = "host"
        init         = true
        security_opt = ["label=type:tf_worker.process"]

        volumes = [
          "{{ nomad_home_dir }}/.ssh/id_artemis:/CONFIG-SECRETS/id_rsa_artemis:ro,z",
          "/etc/citool.d/environment.yaml:/CONFIG/environment.yaml:ro",
          "/etc/citool.d/config:/CONFIG-SECRETS/config:ro",
          "{{ nomad_data_dir }}/alloc/${NOMAD_ALLOC_ID}/alloc:/var/ARTIFACTS/${NOMAD_META_REQUEST_ID}:z",
          "{{ nomad_podman_socket_path | default('/run/podman/podman.sock') }}:/run/podman/podman.sock",
          "{{ nomad_home_dir }}/.ssh/id_artifacts:/root/.ssh/id_ed25519:ro,z",
{% if nomad_user != "root" %}
          "{{ nomad_containers_conf_path }}:/etc/containers/containers.conf",
{% endif %}
        ]

        entrypoint = ["/bin/tf-sti"]
      }

      env {
        CONTAINER_HOST = "unix:///run/podman/podman.sock"
        ARTIFACTS_DIR  = "/var/ARTIFACTS"
        API_URL        = "http://{{ api_hostname }}/v0.1"
        ARTIFACTS_URL  = "http://{{ artifacts_hostname }}"

        CITOOL_CONFIG_IMAGE         = "${NOMAD_META_CITOOL_CONFIG_IMAGE}"
        CITOOL_CONFIG_IMAGE_DEFAULT = "{{ citool_config_container_image }}"

        REQUEST_TIMEOUT = "${NOMAD_META_REQUEST_TIMEOUT}"
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
