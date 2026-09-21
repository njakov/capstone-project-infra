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
#   - two conditioned projectIamAdmin bindings (each hasOnly list is at most 10 roles)
#   - bucket roles/storage.objectAdmin only (not storage.admin)
#   - TokenCreator for YOUR_USER_EMAIL on terraform-sa
#
# Also creates project custom roles (terraform-sa has no roles/iam.roleAdmin):
#   infraRunnerWorkloadIdentityAdmin — get, getIamPolicy, setIamPolicy. No keys.
#     Bootstrap binds it on the app, app-runner, and external-secrets SAs.
#   arcAppDeploy — cluster get, getCredentials, connect, and namespace get.
#     Bootstrap binds it on the app-runner SA. No secret or RBAC-admin verbs.
#
# Before granting conditioned projectIamAdmin, removes any unconditioned binding
# (--condition=None) and any previous conditional projectIamAdmin binding for
# this SA, so an old allow-list is not OR'd with the new ones.

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

# Workload-identity policy admin for the infra runner. Bound later by
# modules/bootstrap-iam on the app, app-runner, and external-secrets SAs. No key permissions.
WI_ADMIN_ROLE_ID="infraRunnerWorkloadIdentityAdmin"
WI_ADMIN_ROLE_PERMISSIONS="iam.serviceAccounts.get,iam.serviceAccounts.getIamPolicy,iam.serviceAccounts.setIamPolicy"
WI_ADMIN_ROLE_TITLE="Infra Runner Workload Identity Admin"
WI_ADMIN_ROLE_DESCRIPTION="get, getIamPolicy, and setIamPolicy on service accounts. No key creation."

# Deploy identity for ARC. Kubernetes object access is RBAC in petclinic, not this role.
# getCredentials is required by gcloud container clusters get-credentials (IP endpoint).
# Namespace create/update stay off: Terraform owns the petclinic namespace.
ARC_DEPLOY_ROLE_ID="arcAppDeploy"
ARC_DEPLOY_ROLE_PERMISSIONS="container.clusters.get,container.clusters.getCredentials,container.clusters.connect,container.namespaces.get"
ARC_DEPLOY_ROLE_TITLE="ARC App Deploy"
ARC_DEPLOY_ROLE_DESCRIPTION="Cluster get, getCredentials, connect, and namespace get. No secrets or RBAC admin."

ensure_project_custom_role() {
  local role_id="$1"
  local title="$2"
  local description="$3"
  local permissions="$4"
  local role_deleted

  echo "---"
  echo "Ensuring custom role ${role_id}..."

  if role_deleted="$(gcloud iam roles describe "${role_id}" \
    --project="${PROJECT_ID}" \
    --format='value(deleted)' 2>/dev/null)"; then
    if [ "${role_deleted}" = "True" ] || [ "${role_deleted}" = "true" ]; then
      echo "Custom role is soft-deleted; undeleting, then resetting permissions."
      gcloud iam roles undelete "${role_id}" \
        --project="${PROJECT_ID}" \
        --quiet
    else
      echo "Custom role already exists; resetting permissions."
    fi
    gcloud iam roles update "${role_id}" \
      --project="${PROJECT_ID}" \
      --title="${title}" \
      --description="${description}" \
      --permissions="${permissions}" \
      --stage=GA \
      --quiet
  else
    gcloud iam roles create "${role_id}" \
      --project="${PROJECT_ID}" \
      --title="${title}" \
      --description="${description}" \
      --permissions="${permissions}" \
      --stage=GA \
      --quiet
  fi
}

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

ensure_project_custom_role \
  "${WI_ADMIN_ROLE_ID}" \
  "${WI_ADMIN_ROLE_TITLE}" \
  "${WI_ADMIN_ROLE_DESCRIPTION}" \
  "${WI_ADMIN_ROLE_PERMISSIONS}"

ensure_project_custom_role \
  "${ARC_DEPLOY_ROLE_ID}" \
  "${ARC_DEPLOY_ROLE_TITLE}" \
  "${ARC_DEPLOY_ROLE_DESCRIPTION}" \
  "${ARC_DEPLOY_ROLE_PERMISSIONS}"

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

# Drop every conditional projectIamAdmin binding for terraform-sa, including the
# retired single allow-list and any previous copy of the two new titles.
# Unconditioned bindings are removed above and are left untouched here.
echo "---"
echo "Replacing conditional projectIamAdmin bindings for ${SA_EMAIL} (including ${TERRAFORM_SA_IAM_BINDER_RETIRED_TITLE})..."
POLICY_FILE="$(mktemp)"
FILTERED_POLICY_FILE="$(mktemp)"
trap 'rm -f "${POLICY_FILE}" "${FILTERED_POLICY_FILE}"' EXIT
gcloud projects get-iam-policy "${PROJECT_ID}" --format=json > "${POLICY_FILE}"
python3 - "${POLICY_FILE}" "serviceAccount:${SA_EMAIL}" "${FILTERED_POLICY_FILE}" <<'PY'
import json
import sys

source, member, dest = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    policy = json.load(handle)

role = "roles/resourcemanager.projectIamAdmin"
kept = []
removed = 0
for binding in policy.get("bindings", []):
    conditioned = bool(binding.get("condition"))
    members = binding.get("members", [])
    if binding.get("role") == role and conditioned and member in members:
        removed += 1
        remaining = [item for item in members if item != member]
        if remaining:
            binding["members"] = remaining
            kept.append(binding)
        continue
    kept.append(binding)

policy["bindings"] = kept
with open(dest, "w", encoding="utf-8") as handle:
    json.dump(policy, handle)
print(f"Removed {removed} conditional projectIamAdmin binding(s) for {member}.")
PY
gcloud projects set-iam-policy "${PROJECT_ID}" "${FILTERED_POLICY_FILE}" --quiet >/dev/null

grant_conditioned_project_iam() {
  local title="$1"
  local description="$2"
  local expression="$3"
  local condition_file

  condition_file="$(mktemp)"
  # The CEL expression contains commas, which break
  # --condition=expression=...,title=...,description=... field splitting.
  cat > "${condition_file}" <<EOF
expression: "${expression}"
title: ${title}
description: ${description}
EOF
  echo "---"
  echo "Granting conditioned roles/resourcemanager.projectIamAdmin..."
  echo "  title: ${title}"
  echo "  expression: ${expression}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/resourcemanager.projectIamAdmin" \
    --condition-from-file="${condition_file}" \
    --quiet >/dev/null
  rm -f "${condition_file}"
}

grant_conditioned_project_iam \
  "$(terraform_sa_iam_binder_workload_title)" \
  "$(terraform_sa_iam_binder_workload_description)" \
  "$(terraform_sa_iam_binder_workload_expression)"

grant_conditioned_project_iam \
  "$(terraform_sa_iam_binder_scoped_title)" \
  "$(terraform_sa_iam_binder_scoped_description)" \
  "$(terraform_sa_iam_binder_scoped_expression)"

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
