#!/bin/bash
# ==============================================================================
# NEGATIVE IAM TESTS (teaching demo)
# ==============================================================================
# Usage: ./scripts/negative-iam-tests.sh <env>
# Example: ./scripts/negative-iam-tests.sh dev
#
# Expects PERMISSION_DENIED for each case. Run after setup_gcp + bootstrap with
# terraform-sa still enabled (tests 1–2) and the infra runner SA present (test 3).
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

TF_SA="terraform-sa@${PROJECT_ID}.iam.gserviceaccount.com"
RUNNER_SA="github-infra-runner-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
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

echo ""
if [ "${failures}" -eq 0 ]; then
  echo "All negative IAM tests denied as expected."
  exit 0
fi
echo "${failures} negative IAM test(s) did not deny as expected."
exit 1
