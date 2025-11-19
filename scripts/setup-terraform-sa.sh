#!/bin/bash

# --- Configuration (UPDATE THESE) ---
export PROJECT_ID="teak-advice-475415-i2"
export SA_NAME="terraform-sa"
export YOUR_USER_EMAIL="nina.jakovljevic11@gmail.com"
# ------------------------------------

# Exit script on any error
set -e

export SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

echo "Enabling necessary APIs..."
gcloud services enable iam.googleapis.com \
    cloudresourcemanager.googleapis.com \
    serviceusage.googleapis.com \
    container.googleapis.com \
    compute.googleapis.com \
    sqladmin.googleapis.com \
    secretmanager.googleapis.com \
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

# --- NEW: Define roles in an array ---
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

  # For granting IAM permissions (the fix from our last step)
  "roles/resourcemanager.projectIamAdmin"
)

echo "---"
echo "Granting IAM roles to '${SA_EMAIL}'..."

# --- NEW: Iterate over the array ---
for role in "${ROLES_TO_GRANT[@]}"; do
  echo "Granting role: ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None
done

echo "---"
echo "Granting YOU ($YOUR_USER_EMAIL) permission to impersonate this SA..."
# This REPLACES the JSON key file
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