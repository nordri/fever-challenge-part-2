#!/usr/bin/env bash

set -euo pipefail

echo "==> Starting HTTPS proxy"

API_ID=$(terraform -chdir=terraform output -raw api_gateway_id)

if [[ -z "$API_ID" ]]; then
    echo "ERROR: API Gateway ID not found" >&2
    exit 1
fi

API_ID="$API_ID" docker compose up -d proxy

echo "    HTTPS proxy is ready"

