#!/usr/bin/env bash

set -euo pipefail

SECRET_ID="access-events/api-key"
API_KEY_NAME="access-events"
USAGE_PLAN_NAME="access-events"

echo "==> Configuring API Gateway API key"

# Retrieve the secret value if it already exists.
API_KEY=$(
  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ID" \
    --query SecretString \
    --output text 2>/dev/null || true
)

# Generate and store the API key only if the secret has no value yet.
if [[ -z "$API_KEY" || "$API_KEY" == "None" ]]; then
  echo "    Generating API key"

  API_KEY=$(openssl rand -hex 32)

  aws secretsmanager put-secret-value \
    --secret-id "$SECRET_ID" \
    --secret-string "$API_KEY" \
    >/dev/null
else
  echo "    Existing secret found"
fi

# Find the API Gateway API key if it already exists.
API_KEY_ID=$(
  aws apigateway get-api-keys \
    --query "items[?name=='${API_KEY_NAME}'].id | [0]" \
    --output text
)

if [[ -z "$API_KEY_ID" || "$API_KEY_ID" == "None" ]]; then
  echo "    Creating API Gateway API key"

  API_KEY_ID=$(
    aws apigateway create-api-key \
      --name "$API_KEY_NAME" \
      --enabled \
      --value "$API_KEY" \
      --query id \
      --output text
  )
else
  echo "    Existing API Gateway API key found"
fi

# Find the Usage Plan provisioned by Terraform.
USAGE_PLAN_ID=$(
  aws apigateway get-usage-plans \
    --query "items[?name=='${USAGE_PLAN_NAME}'].id | [0]" \
    --output text
)

if [[ -z "$USAGE_PLAN_ID" || "$USAGE_PLAN_ID" == "None" ]]; then
  echo "ERROR: Usage Plan '${USAGE_PLAN_NAME}' not found" >&2
  exit 1
fi

# Check whether the API key is already associated with the Usage Plan.
ASSOCIATED_KEY_ID=$(
  aws apigateway get-usage-plan-keys \
    --usage-plan-id "$USAGE_PLAN_ID" \
    --query "items[?id=='${API_KEY_ID}'].id | [0]" \
    --output text
)

if [[ -z "$ASSOCIATED_KEY_ID" || "$ASSOCIATED_KEY_ID" == "None" ]]; then
  echo "    Associating API key with Usage Plan"

  aws apigateway create-usage-plan-key \
    --usage-plan-id "$USAGE_PLAN_ID" \
    --key-id "$API_KEY_ID" \
    --key-type API_KEY \
    >/dev/null
else
  echo "    API key already associated with Usage Plan"
fi

echo "==> API key configuration complete"
