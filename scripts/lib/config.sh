#!/bin/bash
# Shared helpers for resolving GCP identifiers from env / tfvars.
# Source from other scripts:  source "$(dirname "$0")/lib/config.sh"
#
# Resolution order:
#   PROJECT_ID      — env, else project_id from tfvars (required)
#   REGION          — env, else region from tfvars, else europe-west1
#   YOUR_USER_EMAIL — env, else gcloud config get-value account (required when resolve_user_email is called)
#   BUCKET_NAME     — always terraform-state-bucket-${PROJECT_ID}
#
# IAM (Phase 3): TERRAFORM_SA_ROLES + binder CEL helpers are the single source of
# truth for setup-terraform-sa.sh. bootstrap-env.sh must never grant IAM.
#
# Also: require_terraform_sa_enabled / require_terraform_sa_impersonation.

# Project roles granted directly to terraform-sa (unconditioned).
# Does NOT include projectIamAdmin (granted separately with CEL) or
# project-level serviceAccountUser (escalate-via-VM; creator auto-grant is enough).
TERRAFORM_SA_ROLES=(
  "roles/compute.networkAdmin"
  "roles/compute.instanceAdmin.v1"
  "roles/compute.securityAdmin"
  "roles/iam.serviceAccountAdmin"
  "roles/serviceusage.serviceUsageConsumer"
)

# Roles terraform-sa may grant/revoke via conditioned projectIamAdmin.
# Do not add owner/editor/projectIamAdmin/securityAdmin/serviceAccountUser/Admin.
TERRAFORM_SA_IAM_BINDER_ALLOWLIST=(
  "roles/compute.networkAdmin"
  "roles/container.admin"
  "roles/cloudsql.admin"
  "roles/secretmanager.admin"
  "roles/artifactregistry.admin"
  "roles/serviceusage.serviceUsageConsumer"
  "roles/logging.logWriter"
  "roles/monitoring.metricWriter"
  "roles/artifactregistry.reader"
  "roles/artifactregistry.writer"
  "roles/container.developer"
  "roles/cloudsql.client"
)

# CEL expression for conditioned roles/resourcemanager.projectIamAdmin.
terraform_sa_iam_binder_condition_expression() {
  local joined=""
  local role
  for role in "${TERRAFORM_SA_IAM_BINDER_ALLOWLIST[@]}"; do
    if [ -n "${joined}" ]; then
      joined="${joined}, "
    fi
    joined="${joined}'${role}'"
  done
  echo "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${joined}])"
}

terraform_sa_iam_binder_condition_title() {
  echo "terraform-sa-limited-project-iam-admin"
}

terraform_sa_iam_binder_condition_description() {
  echo "Allow terraform-sa to grant or revoke only the allow-listed project IAM roles"
}

# Extract an unquoted or quoted HCL string value for KEY from a tfvars file.
# Usage: tfvars_get <key> <tfvars_file>
tfvars_get() {
  local key="$1"
  local file="$2"
  if [ ! -f "$file" ]; then
    return 1
  fi
  # Match: key = "value"  or  key = value
  sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"]+)\"?.*/\1/p" "$file" | head -n1
}

# Resolve PROJECT_ID, REGION, and BUCKET_NAME.
# Args: optional path to a tfvars file used when env vars are unset.
resolve_gcp_config() {
  local tfvars_file="${1:-}"
  local default_region="europe-west1"

  if [ -z "${PROJECT_ID:-}" ]; then
    if [ -n "$tfvars_file" ]; then
      PROJECT_ID="$(tfvars_get project_id "$tfvars_file" || true)"
    fi
  fi
  if [ -z "${PROJECT_ID:-}" ]; then
    echo "Error: PROJECT_ID is not set." >&2
    echo "Export PROJECT_ID or provide a tfvars file with project_id (e.g. environments/bootstrap/<env>.tfvars)." >&2
    return 1
  fi
  export PROJECT_ID

  if [ -z "${REGION:-}" ]; then
    if [ -n "$tfvars_file" ]; then
      REGION="$(tfvars_get region "$tfvars_file" || true)"
    fi
  fi
  REGION="${REGION:-$default_region}"
  export REGION

  export BUCKET_NAME="terraform-state-bucket-${PROJECT_ID}"
}

# Resolve YOUR_USER_EMAIL from env or the active gcloud account.
resolve_user_email() {
  if [ -z "${YOUR_USER_EMAIL:-}" ]; then
    YOUR_USER_EMAIL="$(gcloud config get-value account 2>/dev/null || true)"
  fi
  if [ -z "${YOUR_USER_EMAIL:-}" ] || [ "${YOUR_USER_EMAIL}" = "(unset)" ]; then
    echo "Error: YOUR_USER_EMAIL is not set and gcloud account is unset." >&2
    echo "Export YOUR_USER_EMAIL or run: gcloud auth login" >&2
    return 1
  fi
  export YOUR_USER_EMAIL
}

# Fail closed if terraform-sa is missing or disabled (post-bootstrap lock).
# Requires: SA_EMAIL and PROJECT_ID. Does not create or enable the SA.
require_terraform_sa_enabled() {
  if [ -z "${SA_EMAIL:-}" ]; then
    echo "Error: SA_EMAIL is not set before require_terraform_sa_enabled." >&2
    return 1
  fi
  if [ -z "${PROJECT_ID:-}" ]; then
    echo "Error: PROJECT_ID is not set before require_terraform_sa_enabled." >&2
    return 1
  fi

  local disabled
  if ! disabled="$(gcloud iam service-accounts describe "${SA_EMAIL}" \
    --project="${PROJECT_ID}" --format='value(disabled)' 2>/dev/null)"; then
    echo "Error: Service account ${SA_EMAIL} does not exist." >&2
    echo "Run ./scripts/setup_gcp.sh <env> first (creates SA + least-privilege IAM)." >&2
    return 1
  fi

  # gcloud prints True/False; treat any truthy value as locked.
  case "${disabled}" in
    [Tt]rue|1)
      echo "Error: ${SA_EMAIL} is disabled (bootstrap fails closed while locked)." >&2
      echo "Break-glass:" >&2
      echo "  gcloud iam service-accounts enable ${SA_EMAIL} --project=${PROJECT_ID}" >&2
      echo "  # ensure TokenCreator is still on your user, then re-run bootstrap-env.sh" >&2
      echo "  # re-lock after: ./scripts/lock-terraform-sa.sh <env>" >&2
      return 1
      ;;
  esac

  echo "Service account ${SA_EMAIL} exists and is enabled."
}

# Force local Terraform to act as terraform-sa via keyless impersonation.
# Requires: SA_EMAIL set; user ADC (gcloud auth application-default login — do NOT
# bake --impersonate into ADC); TokenCreator on SA_EMAIL for YOUR_USER_EMAIL.
# Sets GOOGLE_IMPERSONATE_SERVICE_ACCOUNT and fails if impersonation cannot mint a token.
require_terraform_sa_impersonation() {
  if [ -z "${SA_EMAIL:-}" ]; then
    echo "Error: SA_EMAIL is not set before require_terraform_sa_impersonation." >&2
    return 1
  fi

  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "Error: Application Default Credentials are not configured." >&2
    echo "Run (as your user — no --impersonate flag):" >&2
    echo "  gcloud auth application-default login" >&2
    echo "Bootstrap then impersonates ${SA_EMAIL} via GOOGLE_IMPERSONATE_SERVICE_ACCOUNT." >&2
    return 1
  fi

  export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT="${SA_EMAIL}"

  if ! gcloud auth print-access-token \
    --impersonate-service-account="${SA_EMAIL}" >/dev/null 2>&1; then
    echo "Error: cannot impersonate ${SA_EMAIL}." >&2
    echo "Ensure:" >&2
    echo "  1. gcloud auth login (and application-default login) as the user with TokenCreator" >&2
    echo "  2. ./scripts/setup_gcp.sh (or setup-terraform-sa.sh) has granted TokenCreator on this SA" >&2
    echo "  3. ADC is your user identity, not an already-impersonated credential:" >&2
    echo "       gcloud auth application-default login" >&2
    echo "  4. terraform-sa is enabled (disabled SA cannot be impersonated)" >&2
    return 1
  fi

  echo "Terraform will impersonate ${SA_EMAIL} (GOOGLE_IMPERSONATE_SERVICE_ACCOUNT)."
}
