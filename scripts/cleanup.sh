#!/usr/bin/env bash

set -euo pipefail

BUCKET="access-events-raw"

echo "==> Cleaning runtime data"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    aws s3 rm "s3://${BUCKET}" --recursive
    echo "    S3 bucket emptied"
else
    echo "    S3 bucket does not exist"
fi

