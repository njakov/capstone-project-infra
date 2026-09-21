#!/bin/bash

# ==============================================================================
# UNIVERSAL BOOTSTRAP SCRIPT
# ==============================================================================
# Usage: ./scripts/bootstrap-env.sh <env>
# Example: ./scripts/bootstrap-env.sh dev
#          ./scripts/bootstrap-env.sh prod
#
# Identifiers (override via env if needed):
#   PROJECT_ID      — else project_id from environments/bootstrap/<env>.tfvars
#   REGION          — else region from tfvars, else europe-west1
#   YOUR_USER_EMAIL — else gcloud config get-value account
#   BUCKET_NAME     — always terraform-state-bucket-${PROJECT_ID}
#
# This script does NOT grant or revoke IAM. Run ./scripts/setup_gcp.sh <env>
# first (create-bucket + setup-terraform-sa). Here we only:
#   1. Verify terraform-sa exists and is enabled (fail closed if disabled)
#   2. Impersonate terraform-sa
#   3. terraform init + apply for environments/bootstrap
#
# Terraform auth: require_terraform_sa_impersonation exports
# GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=terraform-sa@... (user ADC must exist;
# day-2 CI uses the GCE runner SA instead — see docs/adr/001-runner-isolation.md).
# ==============================================================================

set -e  # Exit on error

# --- 1. INPUT VALIDATION ---
if [ -z "$1" ]; then
  echo "Error: No environment specified."
  echo "Usage: $0 <env>"
  exit 1
fi

ENV="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

BOOTSTRAP_DIR="${SCRIPT_DIR}/../environments/bootstrap"
TFVARS_FILE="${BOOTSTRAP_DIR}/${ENV}.tfvars"

# Check if the tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
  echo "Error: Configuration file not found: ${TFVARS_FILE}"
  echo "Please create '${ENV}.tfvars' in environments/bootstrap/ before running this script."
  exit 1
fi

# --- 2. CONFIGURATION (from env / tfvars; no hardcoded project or email) ---
resolve_gcp_config "$TFVARS_FILE"
resolve_user_email

export SA_NAME="${SA_NAME:-terraform-sa}"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== STARTING BOOTSTRAP FOR ENVIRONMENT: ${ENV} ===${NC}"
echo "PROJECT_ID=${PROJECT_ID} REGION=${REGION} BUCKET_NAME=${BUCKET_NAME}"
echo "YOUR_USER_EMAIL=${YOUR_USER_EMAIL}"
gcloud config set project "$PROJECT_ID"

# ==============================================================================
# STEP 3: PRE-FLIGHT (no IAM writes — setup_gcp.sh / setup-terraform-sa.sh only)
# ==============================================================================

echo -e "\n${BLUE}[1/2] Verifying terraform-sa is present and enabled...${NC}"
require_terraform_sa_enabled

# ==============================================================================
# STEP 4: TERRAFORM APPLY (as terraform-sa via impersonation — not as the human user)
# ==============================================================================
echo -e "\n${BLUE}[2/2] Deploying Bootstrap Layer for ${ENV}...${NC}"

require_terraform_sa_impersonation

cd "$BOOTSTRAP_DIR"

echo "Initializing Terraform state: bootstrap/${ENV}..."
# IMPORTANT: Uses the environment name in the prefix to keep states separate
terraform init \
  -reconfigure \
  -backend-config="bucket=${BUCKET_NAME}" \
  -backend-config="prefix=bootstrap/${ENV}"

echo "Applying configuration using ${ENV}.tfvars..."
terraform apply -var-file="${ENV}.tfvars" -auto-approve

echo -e "\n${GREEN}=== ${ENV} BOOTSTRAP COMPLETE ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Lock terraform-sa (disable after bootstrap — CEL does not constrain serviceAccountAdmin):"
echo "       ./scripts/lock-terraform-sa.sh ${ENV}"
echo "  2. IAP SSH to the infra runner (see terraform output runner_ssh_command)."
echo "  3. Switch to the runner user: sudo -iu runner"
echo "  4. Register the GitHub Actions runner with labels: self-hosted,infra,${ENV}"
echo "  5. Apply environments/${ENV} via infra-pipeline.yml (runs-on: self-hosted,infra,${ENV})"
echo ""
echo "Docs: docs/adr/001-runner-isolation.md"
