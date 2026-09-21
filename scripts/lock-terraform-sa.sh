#!/bin/bash

# ==============================================================================
# LOCK terraform-sa AFTER BOOTSTRAP
# ==============================================================================
# Usage: ./scripts/lock-terraform-sa.sh <env>
# Example: ./scripts/lock-terraform-sa.sh dev
#
# Disables terraform-sa so it cannot use unconstrained project-level
# roles/iam.serviceAccountAdmin (CEL does not constrain that role). Run this
# after a successful ./scripts/bootstrap-env.sh <env>.
#
# Identifiers (override via env if needed):
#   PROJECT_ID — else project_id from environments/bootstrap/<env>.tfvars
#
# Break-glass (destroy bootstrap / re-apply):
#   gcloud iam service-accounts enable "terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
#     --project="${PROJECT_ID}"
#   # TokenCreator must still be on the human (or re-grant from Owner)
#   ./scripts/bootstrap-env.sh <env>
#   ./scripts/lock-terraform-sa.sh <env>
# ==============================================================================

set -e

if [ -z "$1" ]; then
  echo "Error: No environment specified."
  echo "Usage: $0 <env>"
  exit 1
fi

ENV="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

TFVARS_FILE="${SCRIPT_DIR}/../environments/bootstrap/${ENV}.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
  echo "Error: Configuration file not found: ${TFVARS_FILE}"
  exit 1
fi

resolve_gcp_config "$TFVARS_FILE"

SA_NAME="${SA_NAME:-terraform-sa}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Locking ${SA_EMAIL} (project=${PROJECT_ID})..."
echo "Reason: project serviceAccountAdmin on terraform-sa is unconstrained by CEL until disabled."

gcloud iam service-accounts disable "${SA_EMAIL}" --project="${PROJECT_ID}"

echo "Disabled ${SA_EMAIL}."
echo "Day-2 applies use github-infra-runner-sa-${ENV} on the GCE VM (not terraform-sa)."
echo ""
echo "Break-glass: enable the SA, ensure TokenCreator on your user, run bootstrap-env.sh,"
echo "then re-run this script to lock again."
