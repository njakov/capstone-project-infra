#!/bin/bash
# ==============================================================================
# NEGATIVE IAM TESTS (teaching demo)
# ==============================================================================
# Usage: ./scripts/negative-iam-tests.sh <env>
# Example: ./scripts/negative-iam-tests.sh dev
#
# Expects PERMISSION_DENIED for bind/create cases. Run after setup_gcp + bootstrap
# with terraform-sa still enabled (tests 1–2) and the infra / app-runner / node
# SAs present (tests 3–5). Tests 4–5 fail until bootstrap-env.sh revokes leftover
# project-level Artifact Registry bindings. Each impersonated test first checks
# that the caller can mint a token for that service account. Do not treat
# success as a green CI gate — these are manual / demo checks.
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
APP_RUNNER_SA="github-app-runner-sa-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
APP_NAME="$(tfvars_get app_name "$TFVARS_FILE" || true)"
if [ -z "${APP_NAME}" ]; then
  echo "Error: app_name is missing from ${TFVARS_FILE}"
  exit 1
fi
NODE_SA="${APP_NAME}-gke-${ENV}-node-sa@${PROJECT_ID}.iam.gserviceaccount.com"
REGION="${REGION:-europe-west1}"

# Fail closed when the caller cannot act as the service account. A
# PERMISSION_DENIED from a failed impersonation is not evidence the target API
# denied that account.
require_impersonation() {
  local sa="$1"
  local err_file token status payload email

  echo ""
  echo "=== Impersonation preflight: ${sa} ==="
  err_file="$(mktemp)"
  set +e
  token="$(gcloud auth print-identity-token --impersonate-service-account="${sa}" 2>"${err_file}")"
  status=$?
  set -e
  if [ "${status}" -ne 0 ] || [ -z "${token}" ]; then
    echo "FAIL: cannot impersonate ${sa}."
    cat "${err_file}"
    rm -f "${err_file}"
    return 1
  fi
  rm -f "${err_file}"

  email="$(printf '%s' "${token}" | python3 -c 'import base64, json, sys
raw = sys.stdin.read().strip().split(".")[1]
raw = raw.replace("-", "+").replace("_", "/")
raw += "=" * (-len(raw) % 4)
print(json.loads(base64.b64decode(raw)).get("email", ""))')"
  unset token
  if [ "${email}" != "${sa}" ]; then
    echo "FAIL: impersonated identity is '${email}', expected '${sa}'."
    return 1
  fi
  echo "OK: caller can impersonate ${sa}."
}

expect_denied() {
  local label="$1"
  shift
  echo ""
  echo "=== ${label} ==="
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if echo "${output}" | grep -Eqi 'Failed to impersonate|Unable to impersonate|iam.serviceAccounts.getAccessToken|iam.serviceAccounts.getOpenIdToken'; then
    echo "FAIL: impersonation failed. This does not prove the target API denied the service account."
    echo "${output}"
    return 1
  fi
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

# Absence check (not a denial): the app-runner SA must not have this role at
# project scope. Repo-scoped writer in modules/artifact-registry is the only
# grant. Fails until bootstrap-env.sh drops the leftover project binding.
expect_no_project_role() {
  local label="$1"
  local member="$2"
  local role="$3"
  local output status hits

  echo ""
  echo "=== ${label} ==="
  set +e
  output="$(gcloud projects get-iam-policy "${PROJECT_ID}" \
    --flatten="bindings[].members" \
    --filter="bindings.role=${role}" \
    --format="value(bindings.members)" 2>&1)"
  status=$?
  set -e
  if [ "${status}" -ne 0 ]; then
    echo "FAIL: could not read project IAM policy (status=${status})."
    echo "${output}"
    return 1
  fi
  hits="$(printf '%s\n' "${output}" | grep -F "${member}" || true)"
  if [ -n "${hits}" ]; then
    echo "FAIL: ${member} still has project-level ${role}."
    echo "${hits}"
    return 1
  fi
  echo "OK: no project-level ${role} on ${member}."
  return 0
}

failures=0

if ! require_impersonation "${TF_SA}"; then
  failures=$((failures + 1))
else
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
  #    --dry-run so a mistaken grant does not leave a cluster or instance behind.
  if ! expect_denied \
    "2a. Impersonate terraform-sa → gcloud container clusters create --dry-run" \
    gcloud container clusters create "neg-test-denied" \
      --project="${PROJECT_ID}" \
      --region="${REGION}" \
      --num-nodes=1 \
      --impersonate-service-account="${TF_SA}" \
      --dry-run \
      --quiet; then
    failures=$((failures + 1))
  fi

  if ! expect_denied \
    "2b. Impersonate terraform-sa → gcloud sql instances create --dry-run" \
    gcloud sql instances create "neg-test-denied" \
      --project="${PROJECT_ID}" \
      --database-version=MYSQL_8_0 \
      --tier=db-f1-micro \
      --region="${REGION}" \
      --impersonate-service-account="${TF_SA}" \
      --dry-run \
      --quiet; then
    failures=$((failures + 1))
  fi
fi

# 3) Runner must not setIamPolicy on terraform-sa (D6: no SA admin on terraform-sa).
if ! require_impersonation "${RUNNER_SA}"; then
  failures=$((failures + 1))
elif ! expect_denied \
  "3. Impersonate runner → setIamPolicy on terraform-sa" \
  gcloud iam service-accounts add-iam-policy-binding "${TF_SA}" \
    --project="${PROJECT_ID}" \
    --member="user:${YOUR_USER_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --impersonate-service-account="${RUNNER_SA}"; then
  failures=$((failures + 1))
fi

# 4) App-runner SA must not have project-level artifactregistry.writer.
#    Fails until bootstrap-env.sh drops the leftover google_project_iam_member.
if ! expect_no_project_role \
  "4. github-app-runner-sa-${ENV} has no project-level artifactregistry.writer" \
  "serviceAccount:${APP_RUNNER_SA}" \
  "roles/artifactregistry.writer"; then
  failures=$((failures + 1))
fi

# 5) Node SA must not have project-level artifactregistry.reader.
#    The live grant is repository IAM in modules/artifact-registry.
if ! expect_no_project_role \
  "5. ${APP_NAME}-gke-${ENV}-node-sa has no project-level artifactregistry.reader" \
  "serviceAccount:${NODE_SA}" \
  "roles/artifactregistry.reader"; then
  failures=$((failures + 1))
fi

echo ""
if [ "${failures}" -eq 0 ]; then
  echo "All negative IAM tests matched expectations."
  exit 0
fi
echo "${failures} negative IAM test(s) did not match expectations."
exit 1
