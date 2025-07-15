.PHONY: help init plan apply destroy clean validate fmt auth-setup

# Default target
help:
	@echo "Available targets:"
	@echo "  init       - Initialize Terraform"
	@echo "  validate   - Validate Terraform configuration"
	@echo "  fmt        - Format Terraform files"
	@echo "  plan       - Create execution plan"
	@echo "  apply      - Apply configuration"
	@echo "  destroy    - Destroy infrastructure"
	@echo "  clean      - Clean up temporary files"
	@echo "  auth-setup - Set up authentication directory"
	@echo "  deploy     - Run full deployment script"

auth-setup:
	@echo "Setting up authentication directory..."
	@mkdir -p auth
	@if [ ! -f auth/api_token ]; then \
		echo "Enter your API token:"; \
		read -s token; \
		echo "$$token" > auth/api_token; \
	fi
	@if [ ! -f auth/pull_secret.json ]; then \
		echo "Please copy your pull secret to auth/pull_secret.json"; \
	fi
	@if [ ! -f auth/ssh_public_key.pub ]; then \
		echo "Please copy your SSH public key to auth/ssh_public_key.pub"; \
	fi
	@echo "Authentication setup complete"

init:
	terraform init

validate: init
	terraform validate

fmt:
	terraform fmt -recursive

plan: validate
	terraform plan

apply: plan
	terraform apply

destroy:
	terraform destroy

clean:
	rm -f tfplan
	rm -f terraform.tfstate.backup
	rm -f cluster_response.json
	rm -f iso_response.json

deploy:
	chmod +x deploy.sh
	./deploy.sh
