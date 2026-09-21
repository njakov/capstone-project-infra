#!/bin/bash

# Create the Terraform service account and grant least-privilege IAM roles.
# This script is the ONLY IAM writer for terraform-sa. bootstrap-env.sh must
# never call add-iam-policy-binding / remove-iam-policy-binding.
#
# Usage: ./scripts/setup-terraform-sa.sh [env]
#   env — optional; defaults to "dev". Reads environments/bootstrap/<env>.tfvars
#         unless PROJECT_ID / YOUR_USER_EMAIL are already set in the environment.
#
# Identifiers:
#   PROJECT_ID      — env, else project_id from bootstrap tfvars
#   YOUR_USER_EMAIL — env, else gcloud config get-value account
#   BUCKET_NAME     — always terraform-state-bucket-${PROJECT_ID}
#
# Grants (per project):
#   - TERRAFORM_SA_ROLES from lib/config.sh (no project-level serviceAccountUser)
#   - conditioned projectIamAdmin (binder allow-list CEL)
#   - bucket roles/storage.objectAdmin only (not storage.admin)
#   - TokenCreator for YOUR_USER_EMAIL on terraform-sa
#
# Before granting conditioned projectIamAdmin, removes any unconditioned binding
# (--condition=None) so IAM OR does not bypass the CEL constraint.

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
    --description="Terraform SA for Capstone Project (bootstrap / break-glass only)" \
    --project="${PROJECT_ID}"
else
  echo "Service Account already exists, skipping creation."
fi

echo "---"
echo "Removing unconditioned projectIamAdmin (if present) so CEL is not OR'd away..."
# Idempotent: ignore failure when the unconditioned binding is already gone.
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/resourcemanager.projectIamAdmin" \
  --condition=None \
  --quiet >/dev/null 2>&1 \
  && echo "Removed unconditioned roles/resourcemanager.projectIamAdmin." \
  || echo "No unconditioned projectIamAdmin binding to remove (ok)."

echo "---"
echo "Granting project roles to '${SA_EMAIL}' (no project-level serviceAccountUser)..."

for role in "${TERRAFORM_SA_ROLES[@]}"; do
  echo "Granting role: ${role}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
done

CONDITION_EXPRESSION="$(terraform_sa_iam_binder_condition_expression)"
CONDITION_TITLE="$(terraform_sa_iam_binder_condition_title)"
CONDITION_DESCRIPTION="$(terraform_sa_iam_binder_condition_description)"

# Use --condition-from-file: the CEL expression contains commas, which break
# --condition=expression=...,title=...,description=... field splitting.
CONDITION_FILE="$(mktemp)"
trap 'rm -f "${CONDITION_FILE}"' EXIT
cat > "${CONDITION_FILE}" <<EOF
expression: "${CONDITION_EXPRESSION}"
title: ${CONDITION_TITLE}
description: ${CONDITION_DESCRIPTION}
EOF

echo "---"
echo "Granting conditioned roles/resourcemanager.projectIamAdmin..."
echo "  title: ${CONDITION_TITLE}"
echo "  expression: ${CONDITION_EXPRESSION}"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/resourcemanager.projectIamAdmin" \
  --condition-from-file="${CONDITION_FILE}" \
  --quiet >/dev/null

echo "---"
echo "Granting state access on '${BUCKET_NAME}' (roles/storage.objectAdmin only)..."
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin" \
  --quiet >/dev/null

echo "---"
echo "Granting YOU ($YOUR_USER_EMAIL) permission to impersonate this SA..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --member="user:${YOUR_USER_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project="${PROJECT_ID}" \
  --quiet >/dev/null

echo "---"
echo "✅ Setup Complete!"
echo "Service Account '${SA_EMAIL}' is ready."
echo "Your user (${YOUR_USER_EMAIL}) has roles/iam.serviceAccountTokenCreator on it."
echo ""
echo "Local Terraform auth (bootstrap / break-glass only):"
echo "  1. gcloud auth login"
echo "  2. gcloud auth application-default login   # as YOUR user — do NOT pass --impersonate"
echo "  3. ./scripts/bootstrap-env.sh <env>        # sets GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=${SA_EMAIL}"
echo ""
echo "Day-2 env apply does NOT use this SA — infra-pipeline runs as github-infra-runner-sa-{env}"
echo "on the GCE runner (see docs/adr/001-runner-isolation.md)."
echo ""
echo "After a successful bootstrap apply, disable this SA (Phase 4 lock):"
echo "  gcloud iam service-accounts disable ${SA_EMAIL} --project=${PROJECT_ID}"
echo ""
