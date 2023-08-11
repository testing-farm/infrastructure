.DEFAULT_GOAL := help

##@ Infrastructure

# For scale-redhat-worker target, make all additional targets parameters
# https://stackoverflow.com/questions/2214575/passing-arguments-to-make-run
ifeq (create/redhat/worker,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "SCALE_TARGET"
  SCALE_TARGET := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  SCALE_TARGET := $(if $(SCALE_TARGET),$(SCALE_TARGET),1)
  # ...and turn them into do-nothing targets
  $(eval $(SCALE_TARGET):;@:)
endif

# Use force targets instead of listing all the targets we have via .PHONY
# https://www.gnu.org/software/make/manual/html_node/Force-Targets.html#Force-Targets
.FORCE:

.create/redhat/worker%:
	ansible-playbook -v ansible/playbooks/create-redhat-worker.yml

create/redhat/worker: .FORCE  ## Create a Red Hat ranch worker, use `make create/redhat/worker N` to create N workers
	@echo -e "🚀 \033[0;32mcreating $(SCALE_TARGET) worker(s)\033[0m"
	@$(MAKE) -j $(addprefix .create/redhat/worker, $(shell seq 1 $(SCALE_TARGET)))

##@ Pipeline

define run_pipeline_update
	@echo -e "$(1) \033[0;32m$(2)\033[0m"
	ansible-playbook -v -l $(3) -t $(4) ansible/playbooks/testing-farm.yml
endef

update/pipeline/image: .FORCE  ## Update pipeline container image on all ranches
	$(call run_pipeline_update,💿️,updating pipeline image on all ranches,testing_farm_public_workers,testing_farm_redhat_workers,update_image)

update/public/pipeline/image: .FORCE  ## Update pipeline container image on Public ranch
	$(call run_pipeline_update,💿️,updating Public ranch pipeline image,testing_farm_public_workers,update_image)

update/redhat/pipeline/image: .FORCE  ## Update pipeline container image on Red Hat ranch
	$(call run_pipeline_update,💿️,updating Red Hat ranch pipeline image,testing_farm_redhat_workers,update_image)

update/pipeline/config: .FORCE  ## Update pipeline configuration on all ranches
	$(call run_pipeline_update,🛠,updating pipeline configuration on all ranches,testing_farm_public_workers,testing_farm_redhat_workers,update_config)

update/public/pipeline/config: .FORCE  ## Update pipeline configuration on Public ranch
	$(call run_pipeline_update,🛠,updating Public ranch pipeline configuration,testing_farm_public_workers,update_config)

update/redhat/pipeline/config: .FORCE  ## Update pipeline configuration on Red Hat ranch
	$(call run_pipeline_update,🛠,updating Red Hat ranch pipeline configuration,testing_farm_redhat_workers,update_config)

update/pipeline/jobs: .FORCE  ## Update pipeline jobs on all ranches
	$(call run_pipeline_update,⛴️,updating pipeline jobs on all ranches,testing_farm_public_workers,testing_farm_redhat_workers,update_jobs)

update/public/pipeline/jobs: .FORCE  ## Update pipeline jobs on Public ranch
	$(call run_pipeline_update,⛴️,updating Public ranch pipeline jobs,testing_farm_public_workers,update_jobs)

update/redhat/pipeline/jobs: .FORCE  ## Update pipeline jobs on Red Hat ranch
	$(call run_pipeline_update,⛴️,updating Red Hat ranch pipeline jobs,testing_farm_redhat_workers,update_jobs)

##@ Utility

clean: .FORCE  ## Cleanup
	rm -rf $$DIRENV_PATH
	rm -rf $$VIRTUAL_ENV

# See https://www.thapaliya.com/en/writings/well-documented-makefiles/ for details.
reverse = $(if $(1),$(call reverse,$(wordlist 2,$(words $(1)),$(1)))) $(firstword $(1))

help: .FORCE  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make [target]\033[36m\033[0m\n"} /^[a-zA-Z_/-]+:.*?##/ { printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(call reverse, $(MAKEFILE_LIST))
