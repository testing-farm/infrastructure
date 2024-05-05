#!/bin/sh

# This script modifies /root/.ssh/authorized_keys to allow root login.
#
# Some distros (e.g. CentOS) makes root login impossible by specifying
# a command in the options field of the authorized_keys file. The script simply
# deletes all the options and leaves only 'keytype base64-encoded key [comment]'
#
# It was tested on the following cloud-based images:
#    - CentOS-6-x86_64-GenericCloud-released-latest
#    - CentOS-7-x86_64-GenericCloud-released-latest
#    - CentOS-8-x86_64-GenericCloud-released-latest
#
# Intended usage is to pass this script to artemis gluetool module:
#    artemis --post-install-script="~/.citool.d/guest-setup/scripts/enable-root.sh"


sed -i 's/.*ssh-rsa/ssh-rsa/' /root/.ssh/authorized_keys
