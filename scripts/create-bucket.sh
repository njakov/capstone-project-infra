#!/bin/bash

# Create the Terraform state bucket (KMS-encrypted, public access prevention
# enforced) for the given GCP project.
#
# Usage: ./scripts/create-bucket.sh [env]
#   env — optional; defaults to "dev". Reads environments/bootstrap/<env>.tfvars
#         unless PROJECT_ID / REGION are already set in the environment.
#
# Identifiers:
#   PROJECT_ID  — env, else project_id from bootstrap tfvars
#   REGION      — env, else region from tfvars, else europe-west1
#   BUCKET_NAME — always terraform-state-bucket-${PROJECT_ID}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

ENV="${1:-${ENV:-dev}}"
TFVARS_FILE="${SCRIPT_DIR}/../environments/bootstrap/${ENV}.tfvars"

resolve_gcp_config "$TFVARS_FILE"

LOCATION="${REGION}"
KEYRING="terraform-state-keyring"
KEY_NAME="terraform-state-key"

echo "Using PROJECT_ID=${PROJECT_ID} REGION=${LOCATION} BUCKET_NAME=${BUCKET_NAME}"

# Enable required APIs before trying to use them
echo "Enabling required APIs (KMS and Storage) on project ${PROJECT_ID}..."
gcloud services enable cloudkms.googleapis.com \
    storage.googleapis.com \
    --project="${PROJECT_ID}"

echo "Creating KMS Key Ring '${KEYRING}'..."
if ! gcloud kms keyrings describe "${KEYRING}" --location="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud kms keyrings create "${KEYRING}" \
    --location="${LOCATION}" \
    --project="${PROJECT_ID}"
else
  echo "Key Ring already exists, skipping creation."
fi

echo "Creating KMS CryptoKey '${KEY_NAME}'..."
if ! gcloud kms keys describe "${KEY_NAME}" --keyring="${KEYRING}" --location="${LOCATION}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud kms keys create "${KEY_NAME}" \
    --keyring="${KEYRING}" \
    --location="${LOCATION}" \
    --purpose="encryption" \
    --project="${PROJECT_ID}"
else
  echo "CryptoKey already exists, skipping creation."
fi

echo "Authorizing GCS service agent to use the KMS key..."
gcloud storage service-agent --authorize-cmek="projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}" \
  --project="${PROJECT_ID}"

echo "Creating GCS bucket: $BUCKET_NAME in project $PROJECT_ID..."
if ! gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --default-encryption-key="projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}" \
    --uniform-bucket-level-access \
    --public-access-prevention=enforced
  echo "Bucket created successfully."
else
  echo "Bucket already exists, skipping creation."
fi

echo "Enforcing public access prevention on bucket: $BUCKET_NAME..."
gcloud storage buckets update "gs://$BUCKET_NAME" --public-access-prevention=enforced

echo "Enabling versioning on bucket: $BUCKET_NAME..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

echo "Versioning enabled successfully. Your backend bucket is ready."
