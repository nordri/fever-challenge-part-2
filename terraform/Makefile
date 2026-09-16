.PHONY: format validate plan apply destroy

TF_CREDENTIALS = \
	$(if $(AWS_ACCESS_KEY_ID),TF_VAR_aws_access_key="$(AWS_ACCESS_KEY_ID)") \
	$(if $(AWS_SECRET_ACCESS_KEY),TF_VAR_aws_secret_key="$(AWS_SECRET_ACCESS_KEY)") \
	$(if $(AWS_SESSION_TOKEN),TF_VAR_aws_session_token="$(AWS_SESSION_TOKEN)")

TF_ENV = $(TF_TARGET) $(TF_CREDENTIALS)

format:
	terraform fmt -recursive

validate:
	$(TF_ENV) terraform validate

init:
	$(TF_ENV) terraform init

plan:
	$(TF_ENV) terraform plan

apply:
	$(TF_ENV) terraform apply -auto-approve

destroy:
	$(TF_ENV) terraform destroy -auto-approve
