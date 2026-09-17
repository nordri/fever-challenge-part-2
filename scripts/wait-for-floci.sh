#!/usr/bin/env bash

set -euo pipefail

MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1}"

echo "==> Waiting for Floci"

for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
    if aws sts get-caller-identity >/dev/null 2>&1; then
        echo "    Floci is ready"
        exit 0
    fi

    sleep "$SLEEP_SECONDS"
done

echo "ERROR: Floci did not become ready after $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds" >&2
exit 1

