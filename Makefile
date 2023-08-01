.DEFAULT_GOAL := help

.PHONY: clean help create-redhat-worker

##@ Infrastructure

# For scale-redhat-worker target, make all additional targets parameters
# https://stackoverflow.com/questions/2214575/passing-arguments-to-make-run
ifeq (create-redhat-worker,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "SCALE_TARGET"
  SCALE_TARGET := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  SCALE_TARGET := $(if $(SCALE_TARGET),$(SCALE_TARGET),1)
  # ...and turn them into do-nothing targets
  $(eval $(SCALE_TARGET):;@:)
endif

.create-redhat-worker%:
	ansible-playbook -v ansible/playbooks/create-redhat-worker.yml

create-redhat-worker:  ## Create a Red Hat ranch worker, use `make create-redhat-worker N` to create N workers
	@echo -e "🚀 \033[0;32mcreating $(SCALE_TARGET) worker(s)\033[0m"
	@$(MAKE) -j $(addprefix .create-redhat-worker, $(shell seq 1 $(SCALE_TARGET)))

##@ Utility

clean:  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
