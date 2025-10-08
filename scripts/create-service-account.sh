#!/bin/bash

set -e

PROJECT_ID="gd-gcp-internship-devops"
SERVICE_ACCOUNT_NAME="terraform-sa-njakov"
KEY_FILE="gcp-key.json"

USER_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

ROLES_TO_GRANT=(
  "roles/compute.instanceAdmin.v1"
  "roles/compute.loadBalancerAdmin"
  "roles/compute.networkAdmin"
  "roles/compute.securityAdmin"
  "roles/cloudsql.admin"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/iam.serviceAccountUser"
)

echo "Creating Service Account '${SERVICE_ACCOUNT_NAME}'..."

if ! gcloud iam service-accounts describe "${USER_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --display-name="Terraform Service Account For Capstone Project" \
    --description="Terraform Service Account For DevOps Internship Capstone Project" \
    --project="${PROJECT_ID}"
else
  echo "Service Account already exists, skipping creation."
fi

echo "Granting IAM roles to '${SERVICE_ACCOUNT_NAME}'..."
for role in "${ROLES_TO_GRANT[@]}"; do
  echo "Granting role: ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${USER_EMAIL}" \
    --role="${role}" --condition=None
done

echo "Creating and downloading key file '${KEY_FILE}'..."
gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="${USER_EMAIL}" \
    --project="${PROJECT_ID}"


echo ""
echo "All done!"
echo "Your service account key is saved as '${KEY_FILE}'."
echo ""
echo "To authenticate your local terminal, run this command:"
echo "export GOOGLE_APPLICATION_CREDENTIALS=\"$(pwd)/${KEY_FILE}\""

