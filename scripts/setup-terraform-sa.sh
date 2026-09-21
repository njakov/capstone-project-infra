#!/bin/bash

# Create the Terraform service account and grant IAM roles.
#
# Usage: ./scripts/setup-terraform-sa.sh [env]
#   env — optional; defaults to "dev". Reads environments/bootstrap/<env>.tfvars
#         unless PROJECT_ID / YOUR_USER_EMAIL are already set in the environment.
#
# Identifiers:
#   PROJECT_ID      — env, else project_id from bootstrap tfvars
#   YOUR_USER_EMAIL — env, else gcloud config get-value account
#   BUCKET_NAME     — always terraform-state-bucket-${PROJECT_ID}

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

ENV="${1:-${ENV:-dev}}"
TFVARS_FILE="${SCRIPT_DIR}/../environments/bootstrap/${ENV}.tfvars"

resolve_gcp_config "$TFVARS_FILE"
resolve_user_email

export SA_NAME="${SA_NAME:-terraform-sa}"
export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Using PROJECT_ID=${PROJECT_ID} BUCKET_NAME=${BUCKET_NAME}"
echo "YOUR_USER_EMAIL=${YOUR_USER_EMAIL}"

echo "Setting project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

echo "Enabling necessary APIs..."
gcloud services enable iam.googleapis.com \
    iamcredentials.googleapis.com \
    cloudresourcemanager.googleapis.com \
    serviceusage.googleapis.com \
    container.googleapis.com \
    compute.googleapis.com \
    sqladmin.googleapis.com \
    servicenetworking.googleapis.com \
    secretmanager.googleapis.com \
    artifactregistry.googleapis.com \
    --project="${PROJECT_ID}"

echo "---"
echo "Creating Service Account: $SA_NAME..."

if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Terraform Service Account" \
    --description="Terraform SA for Capstone Project" \
    --project="${PROJECT_ID}"
else
  echo "Service Account already exists, skipping creation."
fi

ROLES_TO_GRANT=(
  # For GKE
  "roles/container.admin"

  # For Networking & Runner VM
  "roles/compute.networkAdmin"
  "roles/compute.instanceAdmin.v1"
  "roles/compute.securityAdmin"

  # For Database & Secrets
  "roles/cloudsql.admin"
  "roles/secretmanager.admin"

  # For Enabling APIs & Managing Other SAs
  "roles/serviceusage.serviceUsageConsumer"
  "roles/iam.serviceAccountAdmin"
  "roles/iam.serviceAccountCreator"

  # For granting IAM permissions
  "roles/resourcemanager.projectIamAdmin"
)

echo "---"
echo "Granting IAM roles to '${SA_EMAIL}'..."

for role in "${ROLES_TO_GRANT[@]}"; do
  echo "Granting role: ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None
done

echo "Granting state access on '${BUCKET_NAME}'..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin"

echo "---"
echo "Granting YOU ($YOUR_USER_EMAIL) permission to impersonate this SA..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --member="user:${YOUR_USER_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project="${PROJECT_ID}"

echo "---"
echo "✅ Setup Complete!"
echo "Service Account '${SA_EMAIL}' is ready."
echo "You are configured to impersonate it."
echo ""
echo "To authenticate your local terminal, run this command:"
echo "gcloud auth application-default login --impersonate-service-account=\"${SA_EMAIL}\""
echo ""
