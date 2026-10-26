#!/bin/bash
# Image build: install the storage server, add a placeholder TLS cert and
# enable the services.
# Run from the Containerfile; build ARGs arrive as env vars.
# No storage is mounted and no service is started during the build.
set -euo pipefail

: "${AMAZON_EFS_UTILS_VERSION:?Missing helper version}"

# Bootstrap curl from the base repositories before enabling AWS key checks.
# A file capability accepts an existing curl-minimal without replacing it.
dnf -y --disablerepo=efs-utils install nginx openssh-server \
    stunnel nfs-utils openssl /usr/bin/curl

# Use AWS's signed prebuilt RHEL package, not the failing FIPS source build.
curl --fail --silent --show-error --location \
    https://amazon-efs-utils.aws.com/efs-utils-armored.gpg \
    --output /etc/pki/rpm-gpg/RPM-GPG-KEY-efs-utils.gpg
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-efs-utils.gpg
dnf -y install "amazon-efs-utils-${AMAZON_EFS_UTILS_VERSION}"
dnf -y clean all

# nginx (httpd_t) serves artifacts from the NFS mount (nfs_t); SELinux blocks
# that unless httpd_use_nfs is on (it defaults off). -P persists it in the image.
# setsebool comes from policycoreutils, expected present on the bootc base.
setsebool -P httpd_use_nfs 1

# The local mount point stays root-owned; nginx refuses to start until storage
# is mounted over it.
mkdir -p /var/mnt/s3files
chmod 0755 /var/mnt/s3files
chown root:root /var/mnt/s3files

# Placeholder cert so nginx starts. The server is private, so Let's Encrypt can't
# reach it for HTTP-01: setup/renew_certs.sh issues the real cert for
# redhat.artifacts.testing.farm with DNS-01, and the deploy (TFT-4797) installs it
# over these paths.
mkdir -p /etc/pki/nginx
openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout /etc/pki/nginx/artifacts.key \
    -out /etc/pki/nginx/artifacts.crt \
    -subj "/CN=redhat.artifacts.testing.farm" \
    -addext "subjectAltName=DNS:redhat.artifacts.testing.farm"
chmod 0600 /etc/pki/nginx/artifacts.key
chmod 0644 /etc/pki/nginx/artifacts.crt

# artifacts-storage.service mounts the storage at boot from EC2 user data, see
# /usr/local/libexec/mount-artifacts-storage.
systemctl enable nginx sshd artifacts-storage.service
