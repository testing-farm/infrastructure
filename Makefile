.DEFAULT_GOAL := help

# Use force targets instead of listing all the targets we have via .PHONY
# https://www.gnu.org/software/make/manual/html_node/Force-Targets.html#Force-Targets
.FORCE:

# Root directory with Makefile
ROOT_DIR = $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Help prelude
define PRELUDE

Usage:
  make [target]

endef

# Include maintainer Makefile
ifneq ($(IS_MAINTAINER),)
    include Makefile.maintainer
endif

##@ Install

install/pre-commit:  ## Install pre-commit hooks
	@if test -n "$(IS_MAINTAINER)"; then \
		pre-commit install --config .pre-commit-config-maintainer.yaml; \
	else \
		pre-commit install; \
	fi

install/fedora: .FORCE  ## Install Fedora system dependencies (requires root)
	sudo dnf -y install ansible-core direnv git libffi libffi-devel podman poetry python3.9 rsync yq unzip

##@ Cleanup

clean: .FORCE  ## Cleanup
	rm -rf $(ROOT_DIR)/.direnv
	rm -rf $(ROOT_DIR)/.venv
	rm -rf $$PROJECT_ROOT/.pytest
	find . -name .terragrunt-cache | xargs rm -rf


# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help: .FORCE  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "$(info $(PRELUDE))"} /^[a-zA-Z_/-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
