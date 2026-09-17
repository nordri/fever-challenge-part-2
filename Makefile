SHELL := /bin/bash

AWS_REGION ?= eu-west-1
AWS_ENDPOINT_URL ?= http://localhost:4566

export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export AWS_DEFAULT_REGION := $(AWS_REGION)
export AWS_ENDPOINT_URL := $(AWS_ENDPOINT_URL)

.PHONY: deploy start-floci wait-floci certs lambda terraform api-key start-proxy plan destroy evidence

deploy: start-floci wait-floci certs lambda terraform api-key start-proxy
	@echo
	@echo "Deployment complete"
	@echo "HTTPS endpoint: https://localhost:8443/events"

start-floci:
	@echo "==> Starting Floci"
	docker compose up -d floci

wait-floci:
	@./scripts/wait-for-floci.sh

certs:
	@./scripts/generate-certs.sh

lambda:
	@$(MAKE) -C lambda build

terraform:
	@echo "==> Applying Terraform"
	@$(MAKE) -C terraform init
	@$(MAKE) -C terraform apply

api-key:
	@./scripts/configure-api-key.sh

start-proxy:
	@./scripts/start-proxy.sh

plan: wait-floci
	@$(MAKE) -C terraform plan

destroy:
	@echo "==> Destroying Terraform resources"
	@./scripts/cleanup.sh
	@$(MAKE) -C terraform destroy
	@echo "==> Stopping containers"
	@docker compose down

test:
	@echo "==> Running test"
	@./scripts/test.sh

evidence:
	@./scripts/collect-evidence.sh
