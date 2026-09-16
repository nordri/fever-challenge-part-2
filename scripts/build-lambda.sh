#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LAMBDA_DIR="${PROJECT_ROOT}/lambda"
SRC_DIR="${LAMBDA_DIR}/src"
BUILD_DIR="${LAMBDA_DIR}/build"
PACKAGE_DIR="${BUILD_DIR}/package"
ZIP_FILE="${BUILD_DIR}/lambda.zip"

echo "==> Cleaning previous Lambda build"
rm -rf "${BUILD_DIR}"
mkdir -p "${PACKAGE_DIR}"

echo "==> Installing Lambda dependencies"
python3 -m pip install \
    --requirement "${SRC_DIR}/requirements.txt" \
    --target "${PACKAGE_DIR}"

echo "==> Copying Lambda source"
cp "${SRC_DIR}/handler.py" "${PACKAGE_DIR}/"

echo "==> Creating Lambda ZIP"
(
    cd "${PACKAGE_DIR}"
    zip -qr "${ZIP_FILE}" .
)

echo "==> Lambda package created"
echo "    ${ZIP_FILE}"
