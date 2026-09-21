#!/bin/bash
# ==============================================================================
# NEGATIVE IAM TESTS (teaching demo)
# ==============================================================================
# Usage: ./scripts/negative-iam-tests.sh <env>
# Example: ./scripts/negative-iam-tests.sh dev
#
# Expects PERMISSION_DENIED for each case. Run after setup_gcp + bootstrap with
# terraform-sa still enabled (tests 1–2) and the infra runner SA present (tests 3–4).
# Do not treat success as a green CI gate — these are manual / demo checks.
#
# Identifiers (override via env if needed):
#   PROJECT_ID — else project_id from environments/bootstrap/<env>.tfvars
# ==============================================================================

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Error: No environment specified."
  echo "Usage: $0 <env>"
  exit 1
fi

ENV="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

TFVARS_FILE="${SCRIPT_DIR}/../environments/bootstrap/${ENV}.tfvars"
if [ ! -f "$TFVARS_FILE" ]; then
  echo "Error: Configuration file not found: ${TFVARS_FILE}"
  exit 1
fi

resolve_gcp_config "$TFVARS_FILE"
resolve_user_email

APP_NAME="$(tfvars_get app_name "${TFVARS_FILE}")"
if [ -z "${APP_NAME}" ]; then
  echo "Error: app_name not set in ${TFVARS_FILE}"
  exit 1
fi

TF_SA="terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com"
RUNNER_SA="github-infra-runner-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
APP_SA="${APP_NAME}-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
APP_RUNNER_SA="github-app-runner-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
EXTERNAL_SECRETS_SA="external-secrets-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
REGION="${REGION:-europe-west1}"

expect_denied() {
  local label="$1"
  shift
  echo ""
  echo "=== ${label} ==="
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if echo "${output}" | grep -Eqi 'PERMISSION_DENIED|AccessDeniedException|does not have permission|Caller does not have permission'; then
    echo "OK: got PERMISSION_DENIED as expected."
    return 0
  fi
  if [ "${status}" -eq 0 ]; then
    echo "FAIL: command succeeded (expected denial)."
    echo "${output}"
    return 1
  fi
  echo "FAIL: command failed but denial string not found (status=${status})."
  echo "${output}"
  return 1
}

# Same denial check as expect_denied, for `gcloud iam service-accounts keys create`.
# A successful create writes a private key to disk and a key on the SA. Delete
# both before failing so a bad run does not leave a usable key behind.
expect_key_create_denied() {
  local label="$1"
  local sa_email="$2"
  local key_dir key_file output status key_id

  key_dir="$(mktemp -d)"
  key_file="${key_dir}/key.json"

  echo ""
  echo "=== ${label} ==="
  set +e
  output="$(gcloud iam service-accounts keys create "${key_file}" \
    --iam-account="${sa_email}" \
    --project="${PROJECT_ID}" \
    --impersonate-service-account="${RUNNER_SA}" \
    --quiet 2>&1)"
  status=$?
  set -e

  if echo "${output}" | grep -Eqi 'PERMISSION_DENIED|AccessDeniedException|does not have permission|Caller does not have permission'; then
    rm -rf "${key_dir}"
    echo "OK: got PERMISSION_DENIED as expected."
    return 0
  fi

  key_id=""
  if [ -f "${key_file}" ]; then
    key_id="$(sed -n -E 's/.*"private_key_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${key_file}" | head -n1)"
  fi
  if [ -z "${key_id}" ]; then
    key_id="$(printf '%s\n' "${output}" | sed -n -E 's/.*created key \[([^]]+)\].*/\1/p' | head -n1)"
  fi
  if [ -n "${key_id}" ]; then
    echo "Unexpected key ${key_id} on ${sa_email}; deleting it before failing."
    # Caller identity (Owner), not the runner: cleanup must work even if the
    # runner can create keys but cannot delete them.
    if ! gcloud iam service-accounts keys delete "${key_id}" \
      --iam-account="${sa_email}" \
      --project="${PROJECT_ID}" \
      --quiet; then
      echo "WARN: failed to delete key ${key_id} on ${sa_email}. Delete it manually."
    fi
  fi
  rm -rf "${key_dir}"

  if [ "${status}" -eq 0 ]; then
    echo "FAIL: command succeeded (expected denial)."
    echo "${output}"
    return 1
  fi
  echo "FAIL: command failed but denial string not found (status=${status})."
  echo "${output}"
  return 1
}

failures=0

# 1) terraform-sa must not bind roles/owner (off the binder allow-list).
if ! expect_denied \
  "1. Impersonate terraform-sa → bind roles/owner" \
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="user:${YOUR_USER_EMAIL}" \
    --role="roles/owner" \
    --impersonate-service-account="${TF_SA}" \
    --condition=None; then
  failures=$((failures + 1))
fi

# 2) terraform-sa must not create GKE / SQL (no container.admin / cloudsql.admin).
if ! expect_denied \
  "2a. Impersonate terraform-sa → gcloud container clusters create" \
  gcloud container clusters create "neg-test-denied" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --num-nodes=1 \
    --impersonate-service-account="${TF_SA}" \
    --quiet; then
  failures=$((failures + 1))
fi

if ! expect_denied \
  "2b. Impersonate terraform-sa → gcloud sql instances create" \
  gcloud sql instances create "neg-test-denied" \
    --project="${PROJECT_ID}" \
    --database-version=MYSQL_8_0 \
    --tier=db-f1-micro \
    --region="${REGION}" \
    --impersonate-service-account="${TF_SA}" \
    --quiet; then
  failures=$((failures + 1))
fi

# 3) Runner must not setIamPolicy on terraform-sa (D6: no SA admin on terraform-sa).
if ! expect_denied \
  "3. Impersonate runner → setIamPolicy on terraform-sa" \
  gcloud iam service-accounts add-iam-policy-binding "${TF_SA}" \
    --project="${PROJECT_ID}" \
    --member="user:${YOUR_USER_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --impersonate-service-account="${RUNNER_SA}"; then
  failures=$((failures + 1))
fi

# 4) Runner must not mint keys (WI custom role has no serviceAccountKeys.create).
if ! expect_key_create_denied \
  "4a. Impersonate runner → keys create on app SA" \
  "${APP_SA}"; then
  failures=$((failures + 1))
fi

if ! expect_key_create_denied \
  "4b. Impersonate runner → keys create on app-runner SA" \
  "${APP_RUNNER_SA}"; then
  failures=$((failures + 1))
fi

if ! expect_key_create_denied \
  "4c. Impersonate runner → keys create on terraform-sa" \
  "${TF_SA}"; then
  failures=$((failures + 1))
fi

if ! expect_key_create_denied \
  "4d. Impersonate runner → keys create on external-secrets SA" \
  "${EXTERNAL_SECRETS_SA}"; then
  failures=$((failures + 1))
fi

echo ""
if [ "${failures}" -eq 0 ]; then
  echo "All negative IAM tests denied as expected."
  exit 0
fi
echo "${failures} negative IAM test(s) did not deny as expected."
exit 1
