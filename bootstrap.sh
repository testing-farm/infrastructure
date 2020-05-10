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

# check architecture
[ "$(arch)" != "x86_64" ] && error "Only x86_64 architecture supported sorry :("

#
# .vault_pass is required to be created
#

info "Checking for vault password"
[ -e "$PROJECT_ROOT/.vault_pass" ] || error "Please create '.vault_pass' in project root '$PROJECT_ROOT'"

#
# make sure bin tools dir exists
#
mkdir -p tools/bin

#
# download kubectl
#
if [ ! -e "$PROJECT_ROOT/tools/bin/kubectl" ]; then
    info "Downloading kubectl 1.15"
    curl -Lo $PROJECT_ROOT/tools/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.15.10/2020-02-22/bin/linux/amd64/kubectl
    chmod +x $PROJECT_ROOT/tools/bin/kubectl
fi

#
# download helm
#
if [ ! -e "$PROJECT_ROOT/tools/bin/helm" ]; then
    info "Downloading helm 3.2.1"
    TEMPDIR=$(mktemp -d)
    curl -Lo $TEMPDIR/helm.tar.gz https://get.helm.sh/helm-v3.2.1-linux-amd64.tar.gz
    tar -xvC $TEMPDIR -f $TEMPDIR/helm.tar.gz
    mv $TEMPDIR/linux-amd64/helm $PROJECT_ROOT/tools/bin/helm
    rm -rf $TEMPDIR
fi

#
# setup kubectl
#
if [ "$(command -v kubectl 2>/dev/null)" != "$PROJECT_ROOT/tools/kubectl" ]; then

    # remove the old config if around
    sed -i '/#### bootstrap.sh start ####/,/#### bootstrap.sh end ####/d' $ACTIVATE_SCRIPT

    info "Set up kubectl, krew and some nice plugins"
    echo "#### bootstrap.sh start ####" >> $ACTIVATE_SCRIPT
    echo "export PATH=$PROJECT_ROOT/tools/bin:\$PATH" >> $ACTIVATE_SCRIPT
    echo "export PATH=$PROJECT_ROOT/tools/.krew/bin:\$PATH" >> $ACTIVATE_SCRIPT
    echo "export KREW_ROOT=$PROJECT_ROOT/tools/.krew/" >> $ACTIVATE_SCRIPT

    # download and install krew
    if [ ! -e "$PROJECT_ROOT/tools/bin/krew" ]; then
        export KREW_ROOT=$PROJECT_ROOT/tools/.krew/
        export PATH=$PROJECT_ROOT/tools/.krew/bin:$PATH
        export PATH=$PROJECT_ROOT/tools/bin:$PATH

        info "Downloading and installing krew"
        TEMPDIR=$(mktemp -d)
        curl -Lo $TEMPDIR/krew.tar.gz "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.tar.gz"
        curl -Lo $TEMPDIR/krew.yaml "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.yaml"
        tar -xvC $TEMPDIR -f $TEMPDIR/krew.tar.gz
        mv $TEMPDIR/krew-linux_amd64 $PROJECT_ROOT/tools/bin/krew
        chmod +x $PROJECT_ROOT/tools/bin/krew
        krew install --manifest=$TEMPDIR/krew.yaml --archive=$TEMPDIR/krew.tar.gz
        info "Installing kubectl plugins ctx, ns"
        kubectl krew install ctx
        kubectl krew install ns
        rm -rf $TEMPDIR
    fi

    export AWS_ACCESS_KEY_ID="$(ansible-vault view --vault-password-file .vault_pass secrets/credentials.yml | yq -r .credentials.aws.fedora.access_key)"
    export AWS_SECRET_ACCESS_KEY="$(ansible-vault view --vault-password-file .vault_pass secrets/credentials.yml | yq -r .credentials.aws.fedora.secret_key)"
    export AWS_DEFAULT_REGION="us-east-2"

    info "Set up AWS credentials"
    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> $ACTIVATE_SCRIPT
    echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> $ACTIVATE_SCRIPT
    echo "export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION" >> $ACTIVATE_SCRIPT

    mkdir -p $PROJECT_ROOT/tools/.kube
    export KUBECONFIG="$PROJECT_ROOT/tools/.kube/config"

    info "Set up kubectl for EKS cluster 'testing-farm'"
    echo "export KUBECONFIG=$KUBECONFIG" >> $ACTIVATE_SCRIPT
    aws eks update-kubeconfig --name testing-farm
    echo "kubectl ctx arn:aws:eks:us-east-1:125523088429:cluster/testing-farm" >> $ACTIVATE_SCRIPT
    echo "#### bootstrap.sh end ####" >> $ACTIVATE_SCRIPT
fi

#
# warn about need to enter venv again as we modified the activate script
#
warn "Please make sure to enter virtual environment again via 'poetry shell' to activate all the tools."
