#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting GCP setup..."

echo "Executing create-bucket.sh..."
"${SCRIPT_DIR}/create-bucket.sh"

echo "Executing setup-terraform-sa.sh..."
"${SCRIPT_DIR}/setup-terraform-sa.sh"

echo "All setup scripts have been executed successfully!"