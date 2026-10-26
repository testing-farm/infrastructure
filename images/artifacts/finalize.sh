#!/bin/bash
# Image build: lock down permissions on the copied-in config and provide a
# throwaway TLS cert. Runs after the config COPYs; no service is started and no
# production storage is mounted during the build.
set -euo pipefail

# nginx runs the mount check as ExecStartPre.
chmod 0755 /usr/local/libexec/check-artifacts-mount

# Self-signed TLS cert so nginx starts and testing is unblocked. The real
# host-provisioned cert (TFT-4797) overrides these paths on deploy.
# TODO(TFT-4795): replace with the real certificate.
mkdir -p /etc/pki/nginx
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout /etc/pki/nginx/artifacts.key \
    -out /etc/pki/nginx/artifacts.crt \
    -subj "/CN=redhat.artifacts.testing.farm" \
    -addext "subjectAltName=DNS:redhat.artifacts.testing.farm"
chmod 0600 /etc/pki/nginx/artifacts.key
chmod 0644 /etc/pki/nginx/artifacts.crt
