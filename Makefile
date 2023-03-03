.DEFAULT_GOAL := help

DEV_ENVIRONMENT_FILES := terraform/environments/dev/ranch/public/citool-config/environment.yaml \
                         terraform/environments/dev/ranch/redhat/citool-config/environment.yaml

##@ Utility

$(DEV_ENVIRONMENT_FILES):
	poetry run python setup/generate_environment.py

generate-environment-variables:  ## Generate `environment.yaml` files used in each citool configuration.
	poetry run python setup/generate_environment.py

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
