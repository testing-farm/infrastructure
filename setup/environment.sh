#
# vars
#

LOG="$PROJECT_ROOT/.direnv/envrc.log"
SSH_CONFIG="$DIRENV_PATH/ssh_config"

# create tools dir including .direnv early
mkdir -p $TOOLS_PATH

#
# helpers
#
info() { echo -e "\e[32m$(printf '🍪\n🚀\n🎉\n🚁' | shuf -n1) $@\e[0m"; echo "[+] $@" >> $LOG; }
print_error() { echo -e "\e[31m⛔ $@\e[0m"; echo "[E] $@" >> $LOG; }
error() { print_error $@; exit 1; }
warn() { echo -e "\e[33m❕$@\e[0m"; echo "[!] $@" >> $LOG; }

# no user specific setup yet
test -z "$IS_MAINTAINER" && exit 0

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
# Add required paths
#
PATH_add "$TOOLS_PATH"
PATH_add "$(poetry run bash -c 'echo $VIRTUAL_ENV')/bin"


#
# install ansible content
#
info "install ansible content"
ansible-galaxy install --force -r $PROJECT_ROOT/ansible/requirements.yaml &>> $LOG

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
# setup AWS profiles
#

if [ ! -e "$DIRENV_PATH/.aws" ]; then
    info "setup AWS profiles"

    mkdir -p "$DIRENV_PATH/.aws"
    export AWS_CONFIG_FILE="$DIRENV_PATH/.aws/config"
    export AWS_SHARED_CREDENTIALS_FILE="$DIRENV_PATH/.aws/credentials"
    for profile in $(ansible-vault view --vault-password-file .vault_pass ansible/secrets/credentials.yaml | yq -r ".credentials.aws.profiles | keys | .[]"); do
        access_key="$(ansible-vault view --vault-password-file .vault_pass ansible/secrets/credentials.yaml | yq -r ".credentials.aws.profiles.$profile.access_key")"
        secret_key="$(ansible-vault view --vault-password-file .vault_pass ansible/secrets/credentials.yaml | yq -r ".credentials.aws.profiles.$profile.secret_key")"
        region="$(ansible-vault view --vault-password-file .vault_pass ansible/secrets/credentials.yaml | yq -r ".credentials.aws.profiles.$profile.region")"
        printf "$access_key\n$secret_key\n$region\n\n\n" | aws --profile $profile configure &>> $LOG
    done
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
# setup ssh
#
if [ ! -e "$SSH_CONFIG" ]; then

    info "setup ssh config"

    #
    # create ssh config
    #
    PUBLIC_WORKERS=$(ansible-inventory --list | jq -r '.testing_farm_public_workers.hosts | join(" ")')
    PUBLIC_SERVERS=$(ansible-inventory --list | jq -r '.testing_farm_public_servers.hosts | join(" ")')
    REDHAT_WORKERS=$(ansible-inventory --list | jq -r '.testing_farm_redhat_workers.hosts | join(" ")')
    REDHAT_SERVERS=$(ansible-inventory --list | jq -r '.testing_farm_redhat_servers.hosts | join(" ")')

    # decrypt all ssh keys
    for key in $(find ansible/secrets/ssh/* -maxdepth 1 ! -name '*.pub' ! -name '*.decrypted'); do
        ansible-vault decrypt --vault-password-file $PROJECT_ROOT/.vault_pass --output ${key}.decrypted $key &>> $LOG
    done

    for host in $PUBLIC_WORKERS $PUBLIC_SERVERS $REDHAT_WORKERS $REDHAT_SERVERS; do
        host_vars=$(ansible-inventory --host $host)
        ansible_host=$(jq -r '.ansible_host' <<< "$host_vars")
        ansible_user=$(jq -r '.ansible_user' <<< "$host_vars")
        ssh_private_key=$(jq -r '.ssh_private_key' <<< "$host_vars" | sed "s|{{ ansible_dir }}|$PROJECT_ROOT/ansible|")

        cat >> $DIRENV_PATH/ssh_config <<EOF
Host $host
  Hostname $ansible_host
  User $ansible_user
  IdentityFile ${ssh_private_key}.decrypted
EOF
    done

    echo "/usr/bin/ssh -F $PROJECT_ROOT/.direnv/ssh_config \$@" > $TOOLS_PATH/ssh
    chmod +x $TOOLS_PATH/ssh

    echo "/usr/bin/scp -F $PROJECT_ROOT/.direnv/ssh_config \$@" > $TOOLS_PATH/scp
    chmod +x $TOOLS_PATH/scp
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
    curl -sLo ${TOOLS_PATH}/terragrunt https://github.com/gruntwork-io/terragrunt/releases/download/v0.57.8/terragrunt_linux_amd64
    chmod +x ${TOOLS_PATH}/terragrunt
fi

#
# install butane
#
if [ ! -e "${TOOLS_PATH}/butane" ]; then
    info "install butane"
    curl -sLo "${TOOLS_PATH}/butane" https://github.com/coreos/butane/releases/download/v0.20.0/butane-x86_64-unknown-linux-gnu
    chmod +x "${TOOLS_PATH}/butane"
fi

#
# setup git goodies
#
if ! grep '\[include\]' .git/config &> /dev/null; then
    info "configure git"
    git config --local include.path ../.gitconfig &>> $LOG
fi
