#!/bin/bash
# Shared helpers for resolving GCP identifiers from env / tfvars.
# Source from other scripts:  source "$(dirname "$0")/lib/config.sh"
#
# Resolution order:
#   PROJECT_ID      — env, else project_id from tfvars (required)
#   REGION          — env, else region from tfvars, else europe-west1
#   YOUR_USER_EMAIL — env, else gcloud config get-value account (required when resolve_user_email is called)
#   BUCKET_NAME     — always terraform-state-bucket-${PROJECT_ID}

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
