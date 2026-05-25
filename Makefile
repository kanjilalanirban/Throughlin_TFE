# Throughlin TFE — local lifecycle commands.
# Use these as the alternative to the GitHub Actions workflows when running
# from a developer machine. AWS credentials are picked up from your active
# AWS profile (typically `aws sso login --profile companybrain-admin`).

ENV_DIR := infra/environments/phase0
BOOT_DIR := infra/bootstrap

.PHONY: help up down status outputs init fmt validate plan bootstrap-init bootstrap-apply

help:
	@echo "Lifecycle:"
	@echo "  make up                  Provision the ephemeral stack (~10-15 min)"
	@echo "  make down                Destroy the ephemeral stack (~5-10 min)"
	@echo "  make status              Show whether the stack is up + its endpoints"
	@echo "  make outputs             Print all Terraform outputs"
	@echo ""
	@echo "Development:"
	@echo "  make init                terraform init (phase0)"
	@echo "  make fmt                 terraform fmt -recursive"
	@echo "  make validate            terraform validate (all layers)"
	@echo "  make plan                terraform plan (phase0)"
	@echo ""
	@echo "Bootstrap (one-time, by hand):"
	@echo "  make bootstrap-init      terraform init for the bootstrap layer (LOCAL state)"
	@echo "  make bootstrap-apply     terraform apply for the bootstrap layer"

up:
	@echo ">>> Bringing up phase0 stack..."
	cd $(ENV_DIR) && terraform init -input=false && terraform apply -input=false -auto-approve
	@echo ""
	@echo ">>> Stack up. Endpoints:"
	@$(MAKE) --no-print-directory outputs

down:
	@echo ">>> Tearing down phase0 stack..."
	cd $(ENV_DIR) && terraform init -input=false && terraform destroy -input=false -auto-approve
	@echo ">>> Stack destroyed. Bootstrap is untouched."

status:
	@cd $(ENV_DIR) && terraform init -input=false > /dev/null 2>&1 || true
	@if cd $(ENV_DIR) && terraform state list > /dev/null 2>&1 && [ -n "$$(cd $(ENV_DIR) && terraform state list 2>/dev/null)" ]; then \
		echo "Stack: UP"; \
		echo ""; \
		$(MAKE) --no-print-directory outputs; \
	else \
		echo "Stack: DOWN (no resources in state)"; \
	fi

outputs:
	@cd $(ENV_DIR) && terraform output

init:
	cd $(ENV_DIR) && terraform init -input=false

fmt:
	terraform fmt -recursive infra/

validate:
	@set -e; \
	for dir in $(BOOT_DIR) infra/modules/* $(ENV_DIR); do \
		echo "==> validate $$dir"; \
		(cd "$$dir" && terraform init -backend=false -input=false > /dev/null && terraform validate); \
	done

plan:
	cd $(ENV_DIR) && terraform init -input=false && terraform plan

bootstrap-init:
	cd $(BOOT_DIR) && terraform init

bootstrap-apply:
	cd $(BOOT_DIR) && terraform apply
