#!/bin/bash -e

#
# Bootstrap additional requirements for our infrastructure
#
# POC, ideally this should all land in `tft-admin init` later on
#

#
# What this script does?
#
# 1. Sets up PATH in venv's activate script to use tools from ``tools/`` directory
#
# 2. Configures kubectl so it finds all plugins we use
#

#
# helpers
#
info() { echo -e "\e[32m[+] $@\e[0m"; }
print_error() { echo -e "\e[31m[E] $@\e[0m"; }
error() { print_error $@; exit 1; }
warn() { echo -e "\e[33m[+] $@\e[0m"; }

#
# vars
#
PROJECT_ROOT=$(dirname $(realpath $0))
ACTIVATE_SCRIPT="$VIRTUAL_ENV/bin/activate"

#
# sanity
#

# check if sourced (only for bash for now)
# https://stackoverflow.com/questions/2683279/how-to-detect-if-a-script-is-being-sourced
if [ -n "$BASH_VERSION" ]; then
    (return 0 2>/dev/null) && { print_error "This script must be executed not sourced"; return; }
fi

# check if in virutal env
[ -z "$VIRTUAL_ENV" ] && error "You are not in an virtual env, please run via 'poetry run ./bootstrap.sh'?"

#
# .vault_pass is required to be created
#

[ -e "$PROJECT_ROOT/.vault_pass" ] || error "Please create '.vault_pass' in project root '$PROJECT_ROOT'"

#
# setup kubectl
#
if [ "$(command -v kubectl 2>/dev/null)" != "$PROJECT_ROOT/tools/kubectl" ]; then
	info "Set up kubectl, krew and some nice plugins"
	echo "export PATH=$PROJECT_ROOT/tools/bin:\$PATH" >> $ACTIVATE_SCRIPT
	echo "export PATH=$PROJECT_ROOT/tools/krew/bin:\$PATH" >> $ACTIVATE_SCRIPT
    echo "export KREW_ROOT=$PROJECT_ROOT/tools/krew/" >> $ACTIVATE_SCRIPT

    export AWS_ACCESS_KEY_ID="$(ansible-vault view --vault-password-file .vault_pass secrets/credentials.yml | yq -r .credentials.aws.fedora.access_key)"
    export AWS_SECRET_ACCESS_KEY="$(ansible-vault view --vault-password-file .vault_pass secrets/credentials.yml | yq -r .credentials.aws.fedora.secret_key)"
    export AWS_DEFAULT_REGION="us-east-1"
    
    info "Set up AWS credentials"
    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> $ACTIVATE_SCRIPT 
    echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> $ACTIVATE_SCRIPT 
    echo "export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >> $ACTIVATE_SCRIPT

    mkdir -p $PROJECT_ROOT/tools/.kube
    export KUBECONFIG="$PROJECT_ROOT/tools/.kube/config"

    info "Set up kubectl for EKS cluster 'testing-farm'"
    echo "export KUBECONFIG=$KUBECONFIG" >> $ACTIVATE_SCRIPT
    aws eks update-kubeconfig --name testing-farm
fi

#
# warn about need to reactivate 
#
warn "Please make sure to enter virtual environment again via 'poetry shell' to activate all the tools."
