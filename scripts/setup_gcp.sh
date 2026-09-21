#!/bin/bash

# Orchestrate one-time GCP setup: state bucket + Terraform SA.
#
# Usage: ./scripts/setup_gcp.sh [env]
#   env — optional; passed through to create-bucket.sh and setup-terraform-sa.sh
#         (defaults to "dev" in those scripts). PROJECT_ID / REGION /
#         YOUR_USER_EMAIL may be set in the environment to override tfvars.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_ARG=()
if [ -n "${1:-}" ]; then
  ENV_ARG=("$1")
fi

echo "Starting GCP setup..."

echo "Executing create-bucket.sh..."
"${SCRIPT_DIR}/create-bucket.sh" "${ENV_ARG[@]}"

echo "Executing setup-terraform-sa.sh..."
"${SCRIPT_DIR}/setup-terraform-sa.sh" "${ENV_ARG[@]}"

echo "All setup scripts have been executed successfully!"
