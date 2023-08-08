.DEFAULT_GOAL := help

.PHONY: clean help test-worker-redhat test-worker-public generate-environment-variables

DEV_ENVIRONMENT_VARIABLES := terraform/environments/dev/ranch/public/citool-config/environment.yaml \
                             terraform/environments/dev/ranch/redhat/citool-config/environment.yaml

DEV_ENVIRONMENT_KEYS := terraform/environments/dev/ranch/public/citool-config/id_rsa_artemis.decrypted \
                        terraform/environments/dev/ranch/redhat/citool-config/id_rsa_artemis.decrypted

DEV_ENVIRONMENT_FILES := $(DEV_ENVIRONMENT_VARIABLES) $(DEV_ENVIRONMENT_KEYS)

# pull image by default
CITOOL_EXTRA_PODMAN_ARGS ?= --pull newer

# default worker image
WORKER_IMAGE ?= quay.io/testing-farm/worker:latest

# run in parallel 5 tests
PYTEST_PARALLEL_OPTIONS ?= -d --tx 5*popen//python=python3.9

TESTING_FARM_API_URL ?= https://api.dev.testing-farm.io/v0.1

TESTING_FARM_API_TOKEN ?= $(TESTING_FARM_API_TOKEN_PUBLIC)

##@ Infrastructure

init-dev:  ## Initialize the development environment
	terraform -chdir=terraform/environments/dev init

plan-dev:  ## Plan the building of the development environment
	terraform -chdir=terraform/environments/dev plan

apply-dev:  ## Build the development environment
	terraform -chdir=terraform/environments/dev apply -auto-approve
	aws eks --region us-east-2 update-kubeconfig --name $$TF_VAR_cluster_name

destroy-dev: terminate-artemis-guests-dev  ## Destroy the development environment
	terraform -chdir=terraform/environments/dev destroy -auto-approve

##@ Tests

test-worker-public: wait-artemis-available $(DEV_ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m public -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-podman-args "$(CITOOL_EXTRA_PODMAN_ARGS)" \
	--citool-config terraform/environments/dev/ranch/public/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terraform/environments/dev/ranch/public/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py

test-worker-redhat: $(DEV_ENVIRONMENT_FILES)  ## Run worker integration tests for redhat ranch against dev environment
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m redhat -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-podman-args "$(CITOOL_EXTRA_PODMAN_ARGS)" \
	--citool-config terraform/environments/dev/ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terraform/environments/dev/ranch/redhat/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py

test-guest-setup: wait-artemis-available $(DEV_ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m guest-setup -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-podman-args "$(CITOOL_EXTRA_PODMAN_ARGS)" \
	--citool-config terraform/environments/dev/ranch/public/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terraform/environments/dev/ranch/public/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py

##@ Utility

$(DEV_ENVIRONMENT_FILES):
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py

	# Decrypt ssh keys
	for key in $(DEV_ENVIRONMENT_KEYS); do \
		echo "Decrypting $${key%.decrypted}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key} $${key%.decrypted}; \
	done

generate-environment-files:  ## Generate credential files used in each citool configuration.
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py

	# Decrypt ssh keys
	for key in $(DEV_ENVIRONMENT_KEYS); do \
		echo "Decrypting $${key%.decrypted}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key} $${key%.decrypted}; \
	done

generate-guest-setup:  ## Generate or update guest-setup tests.
	TESTING_FARM_API_TOKEN=${TESTING_FARM_API_TOKEN} TESTING_FARM_API_URL=${TESTING_FARM_API_URL} poetry run python tests/worker/public/generate-guest-setup.py

list-worker-tests:  ## List available worker integration tests
	poetry run pytest $(PYTEST_OPTIONS) -v --basetemp $$PROJECT_ROOT/.pytest --collect-only \
	--citool-config ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--html report.html tests/worker/test_pipeline.py

terminate-artemis-guests-dev:  ## Terminate all EC2 instances from the dev environment created by Artemis
	@bash setup/terminate_artemis_guests_dev.sh

wait-artemis-available:  ## Wait until Artemis is available in the dev environment
	@bash setup/wait_artemis_available_dev.sh

compose-update-public:  ## Update composes in the Public ranch
	poetry run python setup/compose_update_public.py

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV
	rm -rf $$PROJECT_ROOT/.pytest

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
