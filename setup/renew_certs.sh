#!/bin/bash

set -eo pipefail

#
# Renew Let's Encrypt certificates for staging environments
# using DNS-01 challenge via Route53.
#
# Certificates renewed:
#   - *.staging.testing-farm.io + staging.testing-farm.io (staging)
#   - *.staging-ci.testing-farm.io (staging CI)
#
# Requires:
#   - certbot and certbot-dns-route53 installed (via pyproject.toml)
#   - AWS profile with Route53 access (default: fedora_us_east_2)
#   - ansible-vault configured via ansible.cfg
#

AWS_PROFILE="${CERTBOT_AWS_PROFILE:-fedora_us_east_2}"
CERTS_DIR="$PROJECT_ROOT/ansible/secrets/certs"
CERTBOT_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$CERTBOT_DIR"
}
trap cleanup EXIT

error() {
    echo -e "\033[0;31m[E] $*\033[0m"
    exit 1
}

info() {
    echo -e "\033[0;32m[+] $*\033[0m"
}

[ -z "$PROJECT_ROOT" ] && error "PROJECT_ROOT not set"
command -v poetry >/dev/null 2>&1 || error "poetry not found, please setup the development environment (direnv allow)"
poetry run certbot --version >/dev/null 2>&1 || error "certbot not found, please run: poetry install"

# Detect if running in GitLab CI
if [ -n "$CI" ]; then
    [ -z "$GITLAB_PRIVATE_TOKEN" ] && error "GITLAB_PRIVATE_TOKEN not set"
    [ -z "$CI_SERVER_HOST" ] && error "CI_SERVER_HOST not set"
    [ -z "$CI_PROJECT_PATH" ] && error "CI_PROJECT_PATH not set"
fi

# Export AWS credentials for certbot-dns-route53
export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile "$AWS_PROFILE")
export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile "$AWS_PROFILE")
export AWS_DEFAULT_REGION=$(aws configure get region --profile "$AWS_PROFILE")

[ -z "$AWS_ACCESS_KEY_ID" ] && error "Failed to get AWS credentials from profile '$AWS_PROFILE'"

renew_cert() {
    local domain="$1"
    shift
    local cert_dir="$CERTS_DIR/$domain"

    info "Requesting certificate for $domain"
    poetry run certbot certonly \
        --non-interactive \
        --agree-tos \
        --email tft@redhat.com \
        --dns-route53 \
        "$@" \
        --config-dir "$CERTBOT_DIR" \
        --work-dir "$CERTBOT_DIR/work" \
        --logs-dir "$CERTBOT_DIR/logs"

    info "Encrypting certificate for $domain with ansible-vault"
    mkdir -p "$cert_dir"
    ansible-vault encrypt \
        --output "$cert_dir/cert.pem.vault" \
        "$CERTBOT_DIR/live/$domain/cert.pem"

    ansible-vault encrypt \
        --output "$cert_dir/privkey.pem.vault" \
        "$CERTBOT_DIR/live/$domain/privkey.pem"

    # Clean up certbot state for next certificate
    rm -rf "$CERTBOT_DIR"
    CERTBOT_DIR=$(mktemp -d)
}

# Staging: wildcard + bare domain (wildcard doesn't cover bare domain)
renew_cert "staging.testing-farm.io" -d "*.staging.testing-farm.io" -d "staging.testing-farm.io"

# Staging CI: wildcard only
renew_cert "staging-ci.testing-farm.io" -d "*.staging-ci.testing-farm.io"

if [ -z "$CI" ]; then
    info "Not running in GitLab CI, skipping MR creation"
    info "Certificates saved to $CERTS_DIR"
    exit 0
fi

info "Committing updated certificates"
TODAY=$(date +%Y-%m-%d)
BRANCH="update-certs-$TODAY"
git config user.name "TFT Automation"
git config user.email "tft@redhat.com"
git checkout -b "$BRANCH"
git add "$CERTS_DIR/"
git diff --cached --quiet && { info "No certificate changes"; exit 0; }
git commit -m "Renew letsencrypt certificates $TODAY"
git push \
    -o merge_request.create \
    -o merge_request.merge_when_pipeline_succeeds \
    -o merge_request.label="Automation" \
    "https://oauth2:${GITLAB_PRIVATE_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" \
    "$BRANCH"
info "All certificates renewed and committed successfully"
