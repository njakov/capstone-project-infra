#!/bin/bash

# --- Configuration ---
BUCKET_NAME="terraform-state-bucket-njakov-capstone"
PROJECT_ID="gd-gcp-internship-devops"
LOCATION="europe-west1"
KEYRING="terraform-state-keyring-njakov-capstone"
KEY_NAME="terraform-state-key-njakov-capstone"


set -e

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

echo "Creating GCS bucket: $BUCKET_NAME in project $PROJECT_ID..."

echo "Authorizing GCS service agent to use the KMS key..."
gcloud storage service-agent --authorize-cmek="projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}" \
  --project="${PROJECT_ID}"

gcloud storage buckets create "gs://$BUCKET_NAME" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --default-encryption-key="projects/${PROJECT_ID}/locations/${LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}" \
  --uniform-bucket-level-access

echo "Bucket created successfully."

echo "Enabling versioning on bucket: $BUCKET_NAME..."

gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

echo "Versioning enabled successfully. Your backend bucket is ready."

