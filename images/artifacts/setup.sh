#!/bin/bash
# Image build: install the packages, add a placeholder TLS cert and enable the
# services. Run from the Containerfile; build ARGs arrive as env vars.
set -euo pipefail

: "${AMAZON_EFS_UTILS_VERSION:?Missing AMAZON_EFS_UTILS_VERSION}"

# amazon-efs-utils comes from the AWS prebuilt RHEL repo, see efs-utils.repo.
dnf -y install nginx openssh-server stunnel nfs-utils openssl \
    "amazon-efs-utils-${AMAZON_EFS_UTILS_VERSION}"
dnf -y clean all

# nginx (httpd_t) needs httpd_use_nfs to read the NFS mount (nfs_t).
setsebool -P httpd_use_nfs 1

# Placeholder cert so nginx starts. The deploy installs the real cert over it.
mkdir -p /etc/pki/nginx
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout /etc/pki/nginx/artifacts.key \
    -out /etc/pki/nginx/artifacts.crt \
    -subj "/CN=redhat.artifacts.testing.farm" \
    -addext "subjectAltName=DNS:redhat.artifacts.testing.farm"
chmod 0600 /etc/pki/nginx/artifacts.key
chmod 0644 /etc/pki/nginx/artifacts.crt

systemctl enable nginx sshd artifacts.service
