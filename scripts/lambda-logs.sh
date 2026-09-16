#!/usr/bin/env bash

set -euo pipefail

FUNCTION_NAME="${1:-access-events-processor}"
LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"

echo "==> Latest logs for ${FUNCTION_NAME}"

LOG_STREAM="$(
    aws logs describe-log-streams \
        --log-group-name "${LOG_GROUP}" \
        --query 'max_by(logStreams, &lastEventTimestamp).logStreamName' \
        --output text
)"

if [[ -z "${LOG_STREAM}" || "${LOG_STREAM}" == "None" ]]; then
    echo "No log streams found for ${FUNCTION_NAME}" >&2
    exit 1
fi

echo "    Log stream: ${LOG_STREAM}"
echo

aws logs get-log-events \
    --log-group-name "${LOG_GROUP}" \
    --log-stream-name "${LOG_STREAM}" \
    --query 'events[].message' \
    --output json
