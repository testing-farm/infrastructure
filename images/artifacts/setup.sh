#!/bin/bash
# Image build: install the storage server and bake the S3 Files mount unit.
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

# bootc install replaces the active /etc/fstab with only the boot entry, so the
# artifact mount is baked as a systemd unit rather than an fstab line (TFT-4795).
chmod 0755 /usr/local/libexec/render-artifacts-mount
/usr/local/libexec/render-artifacts-mount \
    "$ARTIFACTS_FILESYSTEM_ID" "$ARTIFACTS_MOUNT_TARGET_IP" \
    > /usr/lib/systemd/system/var-mnt-s3files.mount

systemctl enable nginx sshd var-mnt-s3files.mount
