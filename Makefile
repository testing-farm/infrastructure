.DEFAULT_GOAL := help

.PHONY: clean help test-worker-redhat test-worker-public generate-environment-variables

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

# Help prelude
define PRELUDE

Usage:
  make [target]

Variables defaults:

  WORKER_IMAGE = $(WORKER_IMAGE)     ⚙️  test/* targets

endef

# Macro for running terragrunt run-all
define run_terragrunt
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1 terragrunt run-all $2 --terragrunt-non-interactive
endef

# Macro to run terragrunt
define run_terragrunt_app
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1/$2 terragrunt $3
endef


##@ Infrastructure | Infra (Gitlab, etc.)

define run_terragrunt
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1 terragrunt run-all $2 --terragrunt-non-interactive
endef

define run_terragrunt_app
	TERRAGRUNT_WORKING_DIR=terragrunt/environments/$1/$2 terragrunt $3
endef

infra/init:  ## Initialize | infra
	$(call run_terragrunt,infra,init)

infra/plan:  ## Plan deployment | infra
	$(call run_terragrunt,infra,plan)

infra/apply:  ## Deploy | infra
	$(call run_terragrunt,infra,apply)

infra/destroy: ## Destroy | infra
	$(call run_terragrunt,infra,destroy)


##@ Infrastructure | Dev

dev/init:  ## Initialize | dev | all
	$(call run_terragrunt,dev,init)

dev/plan:  ## Plan deployment | dev | all
	$(call run_terragrunt,dev,plan)

dev/plan/eks:  ## Plan deployment | dev | eks
	$(call run_terragrunt_app,dev,eks,plan)

dev/plan/artemis:  ## Plan deployment | dev | artemis
	$(call run_terragrunt_app,dev,artemis,plan)

dev/apply:  ## Deploy | dev | all
	$(call run_terragrunt,dev,apply)

dev/apply/eks:  ## Deploy | dev | eks
	$(call run_terragrunt_app,dev,eks,apply -auto-approve)

dev/apply/artemis:  ## Deploy | dev | artemis
	$(call run_terragrunt_app,dev,artemis,apply -auto-approve)

dev/destroy: terminate/artemis/guests/dev  ## Destroy | dev | all
	$(call run_terragrunt,dev,destroy)


##@ Infrastructure | Staging

staging/init:  ## Initialize | staging | all
	$(call run_terragrunt_app,staging,eks,init)
	$(call run_terragrunt_app,staging,artemis,init)
	$(call run_terragrunt_app,staging,artemis-ci,init)

staging/init/artemis/ci:  ## Initialize | staging | artemis | CI
	$(call run_terragrunt_app,staging,artemis-ci,init)

staging/plan:  ## Plan deployment | staging
	$(call run_terragrunt_app,staging,eks,plan)
	$(call run_terragrunt_app,staging,artemis,plan)

staging/plan/eks:  ## Plan deployment | staging | eks
	$(call run_terragrunt_app,staging,eks,plan)

staging/plan/artemis:  ## Plan deployment | staging | artemis
	$(call run_terragrunt_app,staging,artemis,plan)

staging/plan/artemis/ci:  ## Plan deployment | staging | artemis | CI
	$(call run_terragrunt_app,staging,artemis-ci,plan)

staging/apply:  ## Deploy | staging | all
	$(call run_terragrunt_app,staging,eks,apply -auto-approve)
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)

staging/apply/eks:  ## Deploy | staging | eks
	$(call run_terragrunt_app,staging,eks,apply -auto-approve)
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)

staging/apply/artemis:  ## Deploy | staging | artemis
	$(call run_terragrunt_app,staging,artemis,apply -auto-approve)

staging/apply/artemis/ci:  ## Deploy | staging | artemis | CI
	$(call run_terragrunt_app,staging,artemis-ci,apply -auto-approve)

staging/destroy: terminate/artemis/guests/staging  ## Destroy | staging
	$(call run_terragrunt_app,staging,artemis,destroy -auto-approve)
	$(call run_terragrunt_app,staging,eks,destroy -auto-approve)

staging/destroy/artemis/ci: terminate/artemis/guests/staging/ci  ## Destroy | staging | artemis | CI
	$(call run_terragrunt_app,staging,artemis-ci,destroy -auto-approve)

##@ Tests

define run_pytest_gluetool
	poetry run pytest $(PYTEST_OPTIONS) $(PYTEST_PARALLEL_OPTIONS) $2 -vvv --basetemp $$PROJECT_ROOT/.pytest \
	--color=yes \
	--citool-extra-podman-args "$(CITOOL_EXTRA_PODMAN_ARGS)" \
	--citool-config terragrunt/environments/$1/worker/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--variables terragrunt/environments/$1/worker/citool-config/variables.yaml \
	--variables tests/common.yaml \
	--html report.html tests/worker/test_pipeline.py
endef

test/dev/pipeline: wait/artemis/dev generate/dev/citool-config  ## Run worker tests | dev
	$(call run_pytest_gluetool,dev,-m "public and pipeline")

test/dev/compose: wait/artemis/dev generate/dev/citool-config  ## Run compose tests | dev
	$(call run_pytest_gluetool,dev,-m "public and compose")

test/staging/pipeline: wait/artemis/staging generate/staging/citool-config  ## Run worker tests | dev

	$(call run_pytest_gluetool,staging,-m "public and pipeline")

test/staging/pipeline/ci: wait/artemis/staging/ci generate/staging/citool-config/ci  ## Run worker tests | staging | CI

	$(call run_pytest_gluetool,staging,-m "public and pipeline")

test/staging/compose: wait/artemis/staging generate/staging/citool-config  ## Run compose tests | staging

	$(call run_pytest_gluetool,staging,-m "public and compose")

test/staging/compose/ci: wait/artemis/staging/ci generate/staging/citool-config/ci  ## Run compose tests | staging | CI

	$(call run_pytest_gluetool,staging,-m "public and compose")


##@ Utility

$(ENVIRONMENT_FILES):
	# Generate `environment.yaml` variable files
	poetry run python setup/generate_environment.py

	# Decrypt ssh keys
	for key in $(ENVIRONMENT_KEYS); do \
		echo "Decrypting $${key%.decrypted}..."; \
		ansible-vault decrypt --vault-password-file .vault_pass --output $${key} $${key%.decrypted}; \
	done

generate/dev/citool-config:  ## Generate citool-config | dev
	poetry run python setup/generate_environment.py dev

generate/staging/citool-config:  ## Generate citool-config | dev
	poetry run python setup/generate_environment.py staging

generate/staging/citool-config/ci:  ## Generate citool-config | dev | CI
	ARTEMIS_DEPLOYMENT=artemis-ci poetry run python setup/generate_environment.py staging

generate/public/tests/compose:  ## Generate or update compose tests for Public Ranch
	@TESTING_FARM_API_TOKEN=${TESTING_FARM_API_TOKEN_PUBLIC} TESTING_FARM_API_URL=${TESTING_FARM_API_URL} poetry run python setup/generate_compose_tests.py

list-worker-tests:  ## List available worker integration tests
	poetry run pytest $(PYTEST_OPTIONS) -v --basetemp $$PROJECT_ROOT/.pytest --collect-only \
	--citool-config ranch/redhat/citool-config --citool-image $(WORKER_IMAGE) \
	--test-assets tests/worker \
	--html report.html tests/worker/test_pipeline.py

kubeconfig/dev:  ## Update kubeconfig for development environemnt
	aws eks --region us-east-2 update-kubeconfig --name $(DEV_CLUSTER_NAME)

kubeconfig/staging:  ## Update kubeconfig for staging environment
	aws eks --region us-east-1 update-kubeconfig --name testing-farm-staging

kubeconfig/production:  ## Update kubeconfig for production environment
	aws eks --region us-east-1 update-kubeconfig --name testing-farm-production

terminate/artemis/guests/dev:  ## Terminate all EC2 instances created by Artemis | dev
	@bash $$PROJECT_ROOT/setup/terminate_artemis_guests.sh dev

terminate/artemis/guests/staging:  ## Terminate all EC2 instances created by Artemis | staging
	@bash $$PROJECT_ROOT/setup/terminate_artemis_guests.sh staging

terminate/artemis/guests/staging/ci:  ## Terminate all EC2 instances created by Artemis | staging | CI
	@ARTEMIS_DEPLOYMENT=artemis-ci bash $$PROJECT_ROOT/setup/terminate_artemis_guests.sh staging

wait/artemis/dev:  ## Wait until Artemis is available | dev
	@bash setup/wait_artemis_available.sh dev

wait/artemis/staging:  ## Wait until Artemis is available | staging
	@bash setup/wait_artemis_available.sh staging

wait/artemis/staging/ci:  ## Wait until Artemis is available | staging | CI
	@ARTEMIS_DEPLOYMENT=artemis-ci bash setup/wait_artemis_available.sh staging

terminate/eks/ci:  ## Terminate all EKS CI clusters
	@bash $$PROJECT_ROOT/setup/terminate_eks_ci_clusters.sh

compose/update/public:  ## Update composes in the Public ranch
	poetry run python setup/compose_update_public.py

##@ Cleanup

cleanup/staging/ci: kubeconfig/staging  ## Cleanup CI leftovers from staging
	@bash setup/terminate_eks_ci_namespaces.sh

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV
	rm -rf $$PROJECT_ROOT/.pytest

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "$(info $(PRELUDE))"} /^[a-zA-Z_/-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
