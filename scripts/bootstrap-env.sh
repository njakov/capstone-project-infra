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
#   4. After a successful apply, disable terraform-sa (lock-terraform-sa.sh).
#      set -e skips the lock if apply fails.
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

echo -e "\n${BLUE}[1/3] Verifying terraform-sa is present and enabled...${NC}"
require_terraform_sa_enabled

echo "Verifying custom roles from setup-terraform-sa.sh..."
for role_id in infraRunnerWorkloadIdentityAdmin arcAppDeploy; do
  if ! role_deleted="$(gcloud iam roles describe "${role_id}" \
    --project="${PROJECT_ID}" \
    --format='value(deleted)' 2>/dev/null)"; then
    echo "Error: custom role ${role_id} is missing in ${PROJECT_ID}."
    echo "Run ./scripts/setup-terraform-sa.sh ${ENV} first."
    exit 1
  fi
  if [ "${role_deleted}" = "True" ] || [ "${role_deleted}" = "true" ]; then
    echo "Error: custom role ${role_id} is deleted in ${PROJECT_ID}."
    echo "Run ./scripts/setup-terraform-sa.sh ${ENV} first."
    exit 1
  fi
done

# ==============================================================================
# STEP 4: TERRAFORM APPLY (as terraform-sa via impersonation — not as the human user)
# ==============================================================================
echo -e "\n${BLUE}[2/3] Deploying Bootstrap Layer for ${ENV}...${NC}"

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

# set -e: a failed apply never reaches this. Drop Terraform's impersonation
# env so gcloud disables the SA as the human user (lock-terraform-sa.sh).
echo -e "\n${BLUE}[3/3] Locking terraform-sa after successful apply...${NC}"
env -u GOOGLE_IMPERSONATE_SERVICE_ACCOUNT "${SCRIPT_DIR}/lock-terraform-sa.sh" "${ENV}"

echo -e "\n${GREEN}=== ${ENV} BOOTSTRAP COMPLETE ===${NC}"
echo "terraform-sa (${SA_EMAIL}) is disabled."
echo ""
echo "Next steps:"
echo "  1. IAP SSH to the infra runner (see terraform output runner_ssh_command)."
echo "  2. Switch to the runner user: sudo -iu runner"
echo "  3. Register the GitHub Actions runner with labels: self-hosted,infra,${ENV}"
echo "  4. Apply environments/${ENV} via infra-pipeline.yml (runs-on: self-hosted,infra,${ENV})"
echo ""
echo "Docs: docs/adr/001-runner-isolation.md"
