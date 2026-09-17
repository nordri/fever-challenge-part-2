#!/usr/bin/env bash

set -euo pipefail

ENDPOINT="https://localhost:8443/events"
CA_CERT="proxy/certs/ca.crt"
SECRET_ID="access-events/api-key"
DYNAMODB_TABLE="access-events"
S3_BUCKET="access-events-raw"

EVENT_ID="test-$(date +%s)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DATE_PREFIX="$(date -u +%Y/%m/%d)"
S3_KEY="events/${DATE_PREFIX}/${EVENT_ID}.json"

LOG_DIR="logs"
HTTP_EVIDENCE="${LOG_DIR}/https-request-response.txt"

mkdir -p "$LOG_DIR"
: > "$HTTP_EVIDENCE"

RESPONSE_FILE=$(mktemp)
trap 'rm -f "$RESPONSE_FILE"' EXIT

echo "==> Retrieving API key from Secrets Manager"

API_KEY=$(
    aws secretsmanager get-secret-value \
        --secret-id "$SECRET_ID" \
        --query SecretString \
        --output text
)

if [[ -z "$API_KEY" || "$API_KEY" == "None" ]]; then
    echo "ERROR: API key not found" >&2
    exit 1
fi

PAYLOAD=$(cat <<EOF
{
  "event_id": "${EVENT_ID}",
  "timestamp": "${TIMESTAMP}",
  "domain": "automated-test.local",
  "client_ip": "192.0.2.100"
}
EOF
)

echo "==> Testing request without API key"

STATUS=$(
    curl \
        --silent \
        --output "${RESPONSE_FILE}" \
        --write-out "%{http_code}" \
        --cacert "$CA_CERT" \
        --header "Content-Type: application/json" \
        --data "$PAYLOAD" \
        "$ENDPOINT"
)

{
    echo "=== Request without API key ==="
    echo "POST $ENDPOINT"
    echo "Event ID: $EVENT_ID"
    echo
    echo "HTTP status: $STATUS"
    echo "Response:"
    cat "${RESPONSE_FILE}"
    echo
    echo
} >> "$HTTP_EVIDENCE"

if [[ "$STATUS" != "403" ]]; then
    echo "ERROR: Expected HTTP 403 without API key, got $STATUS" >&2
    exit 1
fi

echo "    Authentication rejected correctly: HTTP 403"

echo "==> Testing authenticated HTTPS request"

STATUS=$(
    curl \
        --silent \
        --output "${RESPONSE_FILE}" \
        --write-out "%{http_code}" \
        --cacert "$CA_CERT" \
        --header "Content-Type: application/json" \
        --header "x-api-key: ${API_KEY}" \
        --data "$PAYLOAD" \
        "$ENDPOINT"
)

{
    echo "=== Authenticated HTTPS request ==="
    echo "POST $ENDPOINT"
    echo "TLS verification: enabled"
    echo "CA certificate: $CA_CERT"
    echo "Authentication: x-api-key (value redacted)"
    echo
    echo "Payload:"
    echo "$PAYLOAD"
    echo
    echo "HTTP status: $STATUS"
    echo "Response:"
    cat "${RESPONSE_FILE}"
    echo
} >> "$HTTP_EVIDENCE"

if [[ "$STATUS" != "202" ]]; then
    echo "ERROR: Expected HTTP 202, got $STATUS" >&2
    exit 1
fi

echo "    Event accepted: HTTP 202"

echo "==> Waiting for event processing"

FOUND=false

for attempt in $(seq 1 15); do
    ITEM=$(
        aws dynamodb get-item \
            --table-name "$DYNAMODB_TABLE" \
            --key "{\"event_id\":{\"S\":\"${EVENT_ID}\"}}" \
            --query Item.event_id.S \
            --output text
    )

    if [[ "$ITEM" == "$EVENT_ID" ]]; then
        FOUND=true
        break
    fi

    sleep 1
done

if [[ "$FOUND" != "true" ]]; then
    echo "ERROR: Event was not persisted in DynamoDB" >&2
    exit 1
fi

echo "    DynamoDB record found"

aws s3api head-object \
    --bucket "$S3_BUCKET" \
    --key "$S3_KEY" \
    >/dev/null

echo "    S3 object found"

echo "==> Testing idempotency"

STATUS=$(
    curl \
        --silent \
        --output /dev/null \
        --write-out "%{http_code}" \
        --cacert "$CA_CERT" \
        --header "Content-Type: application/json" \
        --header "x-api-key: ${API_KEY}" \
        --data "$PAYLOAD" \
        "$ENDPOINT"
)

if [[ "$STATUS" != "202" ]]; then
    echo "ERROR: Duplicate request returned HTTP $STATUS" >&2
    exit 1
fi

sleep 2

DDB_COUNT=$(
    aws dynamodb scan \
        --table-name "$DYNAMODB_TABLE" \
        --filter-expression "event_id = :id" \
        --expression-attribute-values "{\":id\":{\"S\":\"${EVENT_ID}\"}}" \
        --query Count \
        --output text
)

S3_COUNT=$(
    aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_KEY" \
        --query 'length(Contents)' \
        --output text
)

if [[ "$DDB_COUNT" != "1" ]]; then
    echo "ERROR: Expected 1 DynamoDB record, found $DDB_COUNT" >&2
    exit 1
fi

if [[ "$S3_COUNT" != "1" ]]; then
    echo "ERROR: Expected 1 S3 object, found $S3_COUNT" >&2
    exit 1
fi

echo "    DynamoDB records: $DDB_COUNT"
echo "    S3 objects:       $S3_COUNT"

echo "Evidence: $HTTP_EVIDENCE"

echo
echo "All tests passed"
echo "Event ID: $EVENT_ID"

