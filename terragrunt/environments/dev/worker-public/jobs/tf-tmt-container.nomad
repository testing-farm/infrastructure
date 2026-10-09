job "tf-tmt-container" {
  type        = "batch"
  datacenters = ["dc1"]

  parameterized {
    meta_required = ["REQUEST_ID"]
    meta_optional = ["CITOOL_CONFIG_IMAGE", "REQUEST_TIMEOUT"]
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
        cpu    = 2000
        memory = 8192
      }

      config {
        # TODO: revert to latest once merged
        image        = "quay.io/testing-farm/worker-public:68d72a1b"
        network_mode = "host"
        init         = true
        security_opt = ["label=type:tf_worker.process"]

        volumes = [
          # The config bundle comes from the config image at runtime: extract_citool_config
          # copies it into /CONFIG (/etc/citool.d) through the host podman.
          # Artemis guest key: the secrets config/artemis sets `ssh-key = ${config_root}/id_rsa_artemis`
          "{{ nomad_home_dir }}/.ssh/id_artemis:/CONFIG-SECRETS/id_rsa_artemis:ro,z",
          # environment.yaml: gluetool eval_context variables, must sit at the bundle root
          "/etc/citool.d/environment.yaml:/CONFIG/environment.yaml:ro",
          # Secrets config dir: the second --module-config-path entry (set_module_config_paths).
          # Kept out of /CONFIG so the config-image extraction can't collide with it.
          # Overrides the public config per key (e.g. api-key in testing-farm-request).
          "/etc/citool.d/config:/CONFIG-SECRETS/config:ro",
          # Each request writes only to its own allocation directory, see the "artifacts-link" task
          "{{ nomad_data_dir }}/alloc/${NOMAD_ALLOC_ID}/alloc:/var/ARTIFACTS/${NOMAD_META_REQUEST_ID}:z",
          "{{ nomad_podman_socket_path }}:/run/podman/podman.sock",
          # TODO: ssh-agent disabled, see the nomad role tasks
          # "{{ nomad_home_dir }}/.ssh/agent.sock:/run/ssh-agent.sock",
          # Default ssh identity of the container root user, the archive module uploads with it
          "{{ nomad_home_dir }}/.ssh/id_artifacts:/root/.ssh/id_ed25519:ro,z",
{% if nomad_user != "root" %}
          "{{ nomad_containers_conf_path }}:/etc/containers/containers.conf",
{% endif %}
        ]

        entrypoint = ["/bin/tf-tmt-container"]
      }

      env {
        CONTAINER_HOST = "unix:///run/podman/podman.sock"
        ARTIFACTS_DIR  = "/var/ARTIFACTS"
        # TODO: ssh-agent disabled, see the nomad role tasks
        # SSH_AUTH_SOCK  = "/run/ssh-agent.sock"
        API_URL        = "http://{{ api_hostname }}/v0.1"
        ARTIFACTS_URL  = "http://{{ artifacts_hostname }}"

        CITOOL_CONFIG_IMAGE         = "${NOMAD_META_CITOOL_CONFIG_IMAGE}"
        CITOOL_CONFIG_IMAGE_DEFAULT = "quay.io/testing-farm/ranch-public:latest"

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
