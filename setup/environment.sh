#
# vars
#
LOG="$PROJECT_ROOT/.direnv/envrc.log"

# create tools dir including .direnv early
mkdir -p $TOOLS_PATH

#
# helpers
#
info() { echo -e "\e[32m$(printf '🍪\n🚀\n🎉\n🚁' | shuf -n1) $@\e[0m"; echo "[+] $@" >> $LOG; }
print_error() { echo -e "\e[31m⛔ $@\e[0m"; echo "[E] $@" >> $LOG; }
error() { print_error $@; exit 1; }
warn() { echo -e "\e[33m❕$@\e[0m"; echo "[!] $@" >> $LOG; }

#
# install all requirements via poetry
#
info "install python deps"
poetry install &>> $LOG

#
# setup git goodies
#
if ! grep '\[include\]' .git/config &> /dev/null; then
    info "configure git"
    git config --local include.path ../.gitconfig &>> $LOG
fi

#
# make sure bin dir exists
#
PATH_add "$TOOLS_PATH"

#
# download helm
#
if [ ! -e "$TOOLS_PATH/helm" ]; then
    info "install helm"
    TEMPDIR=$(mktemp -d)
    curl -sLo $TEMPDIR/helm.tar.gz https://get.helm.sh/helm-v3.11.2-linux-amd64.tar.gz
    tar -xC $TEMPDIR -f $TEMPDIR/helm.tar.gz
    mv $TEMPDIR/linux-amd64/helm $TOOLS_PATH/helm
    rm -rf $TEMPDIR
fi

#
# download and setup kubectl
#
export KUBECONFIG="$DIRENV_PATH/.kube/config"

if [ ! -e "$TOOLS_PATH/kubectl" ]; then

    info "install kubectl"
    curl -sLo $TOOLS_PATH/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl
    chmod +x $TOOLS_PATH/kubectl

    # download and install krew
    export KREW_ROOT=$DIRENV_PATH/.krew/
    PATH_add $DIRENV_PATH/.krew/bin

    info "installing krew and plugins"
    TEMPDIR=$(mktemp -d)
    curl -sLo $TEMPDIR/krew.tar.gz "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew-linux_amd64.tar.gz"
    curl -sLo $TEMPDIR/krew.yaml "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.yaml"
    tar -xC $TEMPDIR -f $TEMPDIR/krew.tar.gz
    mv $TEMPDIR/krew-linux_amd64 $TOOLS_PATH/krew
    chmod +x $TOOLS_PATH/krew
    krew install ctx &>> $LOG
    krew install ns &>> $LOG
    rm -rf $TEMPDIR

    mkdir -p $DIRENV_PATH/.kube
    touch $KUBECONFIG
fi

#
# download terraform
#
if [ ! -e "${TOOLS_PATH}/terraform" ]; then
    info "install terraform"
    TEMPDIR=$(mktemp -d)
    pushd $TEMPDIR &>> $LOG
    curl -sLo terraform.zip https://releases.hashicorp.com/terraform/1.3.3/terraform_1.3.3_linux_amd64.zip
    unzip terraform.zip &>> $LOG
    mv terraform ${TOOLS_PATH}/terraform
    popd &>> $LOG
    rm -rf $TEMPDIR
fi

if [ ! -e "${TOOLS_PATH}/tflint" ]; then
    info "install tflint"
    TEMPDIR=$(mktemp -d)
    pushd $TEMPDIR &>> $LOG
    curl -sLo tflint.zip https://github.com/terraform-linters/tflint/releases/download/v0.42.2/tflint_linux_amd64.zip
    unzip tflint.zip &>> $LOG
    mv tflint ${TOOLS_PATH}/tflint
    popd &>> $LOG
    rm -rf $TEMPDIR
fi

if [ ! -e "${TOOLS_PATH}/tfsec" ]; then
    info "install tfsec"
    curl -sLo ${TOOLS_PATH}/tfsec https://github.com/aquasecurity/tfsec/releases/download/v1.28.1/tfsec-linux-amd64
    chmod +x ${TOOLS_PATH}/tfsec
fi

if [ ! -e "${TOOLS_PATH}/terragrunt" ]; then
    info "install terragrunt"
    curl -sLo ${TOOLS_PATH}/terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v0.48.7/terragrunt_linux_amd64
    chmod +x ${TOOLS_PATH}/terragrunt
fi

#
# setup git goodies
#
if ! grep '\[include\]' .git/config &> /dev/null; then
    info "configure git"
    git config --local include.path ../.gitconfig &>> $LOG
fi
