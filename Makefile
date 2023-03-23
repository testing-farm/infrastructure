.DEFAULT_GOAL := help

.PHONY: clean help test-worker-redhat test-worker-public generate-environment-variables

TEMPLATED_FILES := terraform/environments/*/ranch/*/citool-config/environment.yaml.j2

ENCRYPTED_FILES := terraform/environments/*/ranch/*/citool-config/id_rsa_artemis

# pull image by default
CITOOL_EXTRA_DOCKER_ARGS ?= --pull newer

# default worker image
WORKER_IMAGE ?= quay.io/testing-farm/worker:latest

# run in parallel 5 tests
PYTEST_PARALLEL_OPTIONS ?= -d --tx 5*popen//python=python3.9

##@ Infrastructure

init-dev:  ## Initialize the development environment
	terraform -chdir=terraform/environments/dev init

plan-dev:  ## Plan the building of the development environment
	terraform -chdir=terraform/environments/dev plan

apply-dev:  ## Build the development environment
	terraform -chdir=terraform/environments/dev apply -auto-approve
	aws eks --region us-east-2 update-kubeconfig --name $$TF_VAR_cluster_name

destroy-dev:  ## Destroy the development environment
	terraform -chdir=terraform/environments/dev destroy -auto-approve

##@ Tests

test-worker-public: $(TEMPLATED_FILES)  ## Run worker integration tests for public ranch against dev environment
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m public -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-docker-args "$(CITOOL_EXTRA_DOCKER_ARGS)" \
	--citool-config terraform/environments/dev/ranch/public/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terraform/environments/dev/ranch/public/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py

test-worker-redhat: $(TEMPLATED_FILES)  ## Run worker integration tests for redhat ranch against dev environment
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m redhat -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-docker-args "$(CITOOL_EXTRA_DOCKER_ARGS)" \
	--citool-config terraform/environments/dev/ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terraform/environments/dev/ranch/redhat/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py

##@ Utility

define generate_environment_files
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py $(TEMPLATED_FILES)

	# Decrypt ssh keys
	for key in $(ENCRYPTED_FILES); do \
		echo "Decrypting $${key}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key}.decrypted $${key}; \
	done
endef

$(subst .j2,,$(TEMPLATED_FILES)) $(ENCRYPTED_FILES).decrypted:
	$(call generate_environment_files)

generate-environment-files:  ## Generate credential files used in each citool configuration.
	$(call generate_environment_files)

list-worker-tests:  ## List available worker integration tests
	poetry run pytest $(PYTEST_OPTIONS) -v --basetemp $$PROJECT_ROOT/.pytest --collect-only \
	--citool-config ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--html report.html tests/worker/test_pipeline.py

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV
	rm -rf $$PROJECT_ROOT/.pytest


# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
