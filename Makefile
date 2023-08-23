.DEFAULT_GOAL := help

.PHONY: clean help test-worker-redhat test-worker-public generate-environment-variables

ENVIRONMENT_VARIABLES := terragrunt/environments/dev/worker/citool-config/environment.yaml \
                         terragrunt/environments/staging/worker/citool-config/environment.yaml

ENVIRONMENT_KEYS := terragrunt/environments/dev/worker/citool-config/id_rsa_artemis.decrypted \
                    terragrunt/environments/staging/worker/citool-config/id_rsa_artemis.decrypted

ENVIRONMENT_FILES := $(ENVIRONMENT_VARIABLES) $(ENVIRONMENT_KEYS)

# pull image by default
CITOOL_EXTRA_PODMAN_ARGS ?= --pull newer

# default worker image
WORKER_IMAGE ?= quay.io/testing-farm/worker:latest

# default development cluster name
DEV_CLUSTER_NAME ?= $(or $(TF_VAR_cluster_name),testing-farm-dev-$$USER)

# run in parallel 5 tests
PYTEST_PARALLEL_OPTIONS ?= -d --tx 5*popen//python=python3.9

TESTING_FARM_API_URL ?= https://api.dev.testing-farm.io/v0.1

TESTING_FARM_API_TOKEN ?= $(TESTING_FARM_API_TOKEN_PUBLIC)

##@ Deprecated

# NOTE old development environment will be removed later
old-init-dev:  ## Initialize the development environment
	terraform -chdir=terraform/environments/dev init

old-plan-dev:  ## Plan the building of the development environment
	terraform -chdir=terraform/environments/dev plan

old-apply-dev:  ## Build the development environment
	terraform -chdir=terraform/environments/dev apply -auto-approve
	aws eks --region us-east-2 update-kubeconfig --name $(DEV_CLUSTER_NAME)

old-destroy-dev: terminate-artemis-guests-dev  ## Destroy the development environment
	terraform -chdir=terraform/environments/dev destroy -auto-approve

##@ Infrastructure | Dev

define run_terragrunt
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1 terragrunt run-all $2 --terragrunt-non-interactive
endef

define run_terragrunt_app
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1/$2 terragrunt $3
endef

dev/init:  ## Initialize the development environment
	$(call run_terragrunt,dev,init)

dev/plan:  ## Plan the building of the development environment
	$(call run_terragrunt,dev,plan)

dev/plan/eks:  ## Plan the building of the development environment / eks module only
	$(call run_terragrunt_app,dev,eks,plan)

dev/plan/artemis:  ## Plan the building of the development environment / eks module only
	$(call run_terragrunt_app,dev,artemis,plan)

dev/apply:  ## Build the development environment
	$(call run_terragrunt,dev,apply)
	aws eks --region us-east-2 update-kubeconfig --name $(DEV_CLUSTER_NAME)

dev/apply/eks:  ## Build the development environment / eks module only
	$(call run_terragrunt_app,dev,eks,apply -auto-approve)
	aws eks --region us-east-2 update-kubeconfig --name $(DEV_CLUSTER_NAME)

dev/apply/artemis:  ## Build the development environment / eks module only
	$(call run_terragrunt_app,dev,artemis,apply -auto-approve)

dev/destroy: terminate/artemis/guests/dev  ## Destroy the development environment
	$(call run_terragrunt,dev,destroy)

##@ Infrastructure | Staging

staging/init:  ## Initialize the staging environment
	$(call run_terragrunt_app,staging,eks,init)
	$(call run_terragrunt_app,staging,artemis,init)
	$(call run_terragrunt_app,staging,artemis-ci,init)

staging/plan:  ## Plan the building of the staging environment
	$(call run_terragrunt_app,staging,eks,plan)
	$(call run_terragrunt_app,staging,artemis,plan)

staging/plan/eks:  ## Plan the building of the staging environment / eks module only
	$(call run_terragrunt_app,staging,eks,plan)

staging/plan/artemis:  ## Plan the building of the staging environment / eks module only
	$(call run_terragrunt_app,staging,artemis,plan)

staging/apply:  ## Build the staging environment
	$(call run_terragrunt_app,staging,eks,apply -auto-approve)
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)
	aws eks --region us-east-1 update-kubeconfig --name testing-farm-staging

staging/apply/eks:  ## Build the staging environment / eks module only
	$(call run_terragrunt_app,staging,eks,apply -auto-approve)
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)
	aws eks --region us-east-1 update-kubeconfig --name testing-farm-staging

staging/apply/artemis:  ## Build the staging environment / eks module only
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)

staging/destroy: terminate/artemis/guests/staging  ## Destroy the staging environment
	$(call run_terragrunt_app,staging,artemis,destroy -auto-approve)
	$(call run_terragrunt_app,staging,eks,destroy -auto-approve)

##@ Tests

define run_pytest_gluetool
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) -m $2 -v --basetemp $$PROJECT_ROOT/.pytest \
	--citool-extra-podman-args "$(CITOOL_EXTRA_PODMAN_ARGS)" \
	--citool-config terragrunt/environments/$1/worker/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terragrunt/environments/$1/worker/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py
endef

test/dev/worker: wait/artemis/dev $(ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	$(call run_pytest_gluetool,dev,public)

test/dev/guest-setup: wait/artemis/dev $(ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	$(call run_pytest_gluetool,dev,guest-setup)

test/staging/worker: wait/artemis/staging $(ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	$(call run_pytest_gluetool,staging,public)

test/staging/guest-setup: wait/artemis/staging $(ENVIRONMENT_FILES)  ## Run worker integration tests for public ranch against dev environment
	$(call run_pytest_gluetool,staging,guest-setup)

##@ Utility

$(ENVIRONMENT_FILES):
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py

	# Decrypt ssh keys
	for key in $(ENVIRONMENT_KEYS); do \
		echo "Decrypting $${key%.decrypted}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key} $${key%.decrypted}; \
	done

generate/environment/files:  ## Generate credential files used in each citool configuration.
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py

	# Decrypt ssh keys
	for key in $(ENVIRONMENT_KEYS); do \
		echo "Decrypting $${key%.decrypted}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key} $${key%.decrypted}; \
	done

generate-guest-setup:  ## Generate or update guest-setup tests.
	@TESTING_FARM_API_TOKEN=${TESTING_FARM_API_TOKEN_PUBLIC} TESTING_FARM_API_URL=${TESTING_FARM_API_URL} poetry run python tests/worker/public/generate-guest-setup.py

list-worker-tests:  ## List available worker integration tests
	poetry run pytest $(PYTEST_OPTIONS) -v --basetemp $$PROJECT_ROOT/.pytest --collect-only \
	--citool-config ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--html report.html tests/worker/test_pipeline.py

terminate/artemis/guests/dev:  ## Terminate all EC2 instances from the dev environment created by Artemis
	@bash $$PROJECT_ROOT/setup/terminate_artemis_guests.sh dev

terminate/artemis/guests/staging:  ## Terminate all EC2 instances from the staging environment created by Artemis
	@bash $$PROJECT_ROOT/setup/terminate_artemis_guests.sh staging

wait/artemis/dev:  ## Wait until Artemis is available in the dev environment
	@bash setup/wait_artemis_available.sh dev

wait/artemis/staging:  ## Wait until Artemis is available in the staging environment
	@bash setup/wait_artemis_available.sh staging

terminate/eks/ci:  ## Terminate all EKS CI clusters
	@bash $$PROJECT_ROOT/setup/terminate_eks_ci_clusters.sh

compose-update-public:  ## Update composes in the Public ranch
	poetry run python setup/compose_update_public.py

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV
	rm -rf $$PROJECT_ROOT/.pytest

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_/-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
