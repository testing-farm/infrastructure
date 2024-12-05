#!/bin/sh -x

# This script modifies /root/.ssh/authorized_keys to allow root login.
#
# Some distros (e.g. CentOS) makes root login impossible by specifying
# a command in the options field of the authorized_keys file. The script simply
# deletes all the options and leaves only 'keytype base64-encoded key [comment]'
#
# While we do not need this for images we built, it is needed for images for:
#
# * Image Mode
# * Vanilla RHEL images
# * Custom images based on cloud base images
#

if [ -e /root/.ssh/authorized_keys ]; then
    sed -i 's/.*ssh-rsa/ssh-rsa/' /root/.ssh/authorized_keys
fi
