#!/bin/bash

# ==============================================================================
# UNIVERSAL BOOTSTRAP SCRIPT
# ==============================================================================
# Usage: ./scripts/bootstrap-env.sh <env>
# Example: ./scripts/bootstrap-env.sh dev
#          ./scripts/bootstrap-env.sh prod
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
BOOTSTRAP_DIR="${SCRIPT_DIR}/../environments/bootstrap"
TFVARS_FILE="${BOOTSTRAP_DIR}/${ENV}.tfvars"

# Check if the tfvars file exists
if [ ! -f "$TFVARS_FILE" ]; then
  echo "Error: Configuration file not found: ${TFVARS_FILE}"
  echo "Please create '${ENV}.tfvars' in environments/bootstrap/ before running this script."
  exit 1
fi

# --- 2. CONFIGURATION (Shared) ---
# You can also load these from a .env file if preferred
export PROJECT_ID="project-17c62de2-ec01-476d-908"
export REGION="europe-west1"
export SA_NAME="terraform-sa"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export BUCKET_NAME="terraform-state-bucket-${PROJECT_ID}"
export YOUR_USER_EMAIL="laz.marko2001@gmail.com"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== STARTING BOOTSTRAP FOR ENVIRONMENT: ${ENV} ===${NC}"
gcloud config set project "$PROJECT_ID"

# ==============================================================================
# STEP 3: INFRASTRUCTURE PRE-REQUISITES (Idempotent)
# ==============================================================================
# Only runs once; skips if resources already exist.

# A. Service Account
echo -e "\n${BLUE}[1/3] Verifying Service Account...${NC}"
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "Creating Service Account: $SA_NAME..."
  gcloud iam service-accounts create "${SA_NAME}" --display-name="Terraform Service Account" --project="${PROJECT_ID}"
else
  echo "Service Account '$SA_NAME' exists."
fi

# A.1 Grant Permissions (Safe to re-run)
echo "Ensuring IAM roles..."
ROLES=(
  "roles/container.admin"
  "roles/compute.networkAdmin"
  "roles/compute.instanceAdmin.v1"
  "roles/compute.securityAdmin"
  "roles/cloudsql.admin"
  "roles/secretmanager.admin"
  "roles/serviceusage.serviceUsageConsumer"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountCreator"
  "roles/resourcemanager.projectIamAdmin"
)
for role in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SA_EMAIL}" --role="${role}" --condition=None --quiet >/dev/null
done
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${SA_EMAIL}" --role="roles/storage.objectAdmin" --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" --member="user:${YOUR_USER_EMAIL}" --role="roles/iam.serviceAccountTokenCreator" --project="${PROJECT_ID}" --quiet >/dev/null

# B. State Bucket
echo -e "\n${BLUE}[2/3] Verifying State Bucket...${NC}"
gcloud services enable cloudkms.googleapis.com storage.googleapis.com --project="${PROJECT_ID}" >/dev/null

if ! gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  echo "Creating Bucket: $BUCKET_NAME..."
  # (Simplified creation for brevity - ensures bucket exists)
  gcloud storage buckets create "gs://$BUCKET_NAME" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
  gcloud storage buckets update "gs://$BUCKET_NAME" --versioning
  echo "Bucket created."
else
  echo "Bucket 'gs://$BUCKET_NAME' exists."
fi

# ==============================================================================
# STEP 4: TERRAFORM APPLY
# ==============================================================================
echo -e "\n${BLUE}[3/3] Deploying Bootstrap Layer for ${ENV}...${NC}"

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
echo "  1. IAP SSH to the infra runner (see terraform output runner_ssh_command)."
echo "  2. Switch to the runner user: sudo -iu runner"
echo "  3. Register the GitHub Actions runner with labels: self-hosted,infra,${ENV}"
echo "  4. Apply environments/${ENV} via infra-pipeline.yml (runs-on: self-hosted,infra,${ENV})"
echo ""
echo "Docs: docs/adr/001-runner-isolation.md"