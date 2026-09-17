#!/usr/bin/env bash

set -euo pipefail

DUMP_DIR="dump-cloud"
LOG_DIR="logs"

DYNAMODB_TABLE="access-events"
S3_BUCKET="access-events-raw"
SQS_QUEUE="access-events"
DLQ_QUEUE="access-events-dlq"
SECRET_ID="access-events/api-key"

mkdir -p "$DUMP_DIR" "$LOG_DIR"

echo "==> Collecting cloud state"

echo "    Terraform state"
terraform -chdir=terraform state list \
    > "$DUMP_DIR/terraform-state-list.txt"

terraform -chdir=terraform show \
    > "$DUMP_DIR/terraform-state-show.txt"

echo "    DynamoDB"
aws dynamodb scan \
    --table-name "$DYNAMODB_TABLE" \
    > "$DUMP_DIR/dynamodb-scan.json"

echo "    S3"
aws s3 ls \
    "s3://${S3_BUCKET}" \
    --recursive \
    > "$DUMP_DIR/s3-ls.txt"

echo "    SQS"

QUEUE_URL=$(
    aws sqs get-queue-url \
        --queue-name "$SQS_QUEUE" \
        --query QueueUrl \
        --output text
)

DLQ_URL=$(
    aws sqs get-queue-url \
        --queue-name "$DLQ_QUEUE" \
        --query QueueUrl \
        --output text
)

aws sqs get-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attribute-names All \
    > "$DUMP_DIR/sqs-attributes.json"

aws sqs get-queue-attributes \
    --queue-url "$DLQ_URL" \
    --attribute-names All \
    > "$DUMP_DIR/dlq-attributes.json"

echo "    Lambda"

aws lambda get-function-configuration \
    --function-name access-events-processor \
    > "$DUMP_DIR/lambda-config.json"

aws lambda list-event-source-mappings \
    --function-name access-events-processor \
    > "$DUMP_DIR/event-source-mapping.json"

echo "    API Gateway"

API_ID=$(terraform -chdir=terraform output -raw api_gateway_id)

aws apigateway get-rest-api \
    --rest-api-id "$API_ID" \
    > "$DUMP_DIR/api-gateway.json"

echo "    Secrets Manager metadata"

aws secretsmanager describe-secret \
    --secret-id "$SECRET_ID" \
    > "$DUMP_DIR/secret-metadata.json"

echo "    Lambda logs"

./scripts/lambda-logs.sh \
    > "$LOG_DIR/lambda.log"

echo
echo "Evidence collected"
echo "Cloud state: $DUMP_DIR/"
echo "Logs:        $LOG_DIR/"

