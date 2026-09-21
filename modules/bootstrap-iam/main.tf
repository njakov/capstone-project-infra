# Workload service accounts + project IAM created at bootstrap (chicken-egg).
# Day-2 env apply consumes these emails; WI bindings stay in env (Phase 5).
# D6: runner gets resource-level WI policy admin + serviceAccountUser here —
# not project-level SA admin, and not key minting.
# CEL does not constrain project-level serviceAccountAdmin on terraform-sa;
# lock = disable terraform-sa after bootstrap (scripts/lock-terraform-sa.sh).

locals {
  # Must match environments/{dev,prod} cloud_sql db_instance_name.
  cloud_sql_instance_name = "${var.app_name}-db-${var.env}"

  # artifactregistry.reader is repo-scoped in modules/artifact-registry.
  # The role stays on terraform-sa-binder-workload so bootstrap can revoke a
  # leftover project-level grant.
  node_sa_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  # arcAppDeploy is created by scripts/setup-terraform-sa.sh.
  # container.developer stays on the terraform-sa CEL allow-list so this
  # binding can be revoked, and is not granted here.
  # Writer is repo-scoped in modules/artifact-registry (the only grant).
  # roles/artifactregistry.writer stays on terraform-sa-binder-workload so
  # bootstrap can revoke a leftover project-level binding.
  app_runner_roles = toset([
    "projects/${var.project_id}/roles/arcAppDeploy",
  ])

  # Created by scripts/setup-terraform-sa.sh (terraform-sa has no roleAdmin).
  # get / getIamPolicy / setIamPolicy only — no iam.serviceAccountKeys.create.
  runner_wi_admin_role = "projects/${var.project_id}/roles/infraRunnerWorkloadIdentityAdmin"
}

# ------------------------------------------------------------------------------
# GKE node SA — account_id: {app}-gke-{env}-node-sa
# ------------------------------------------------------------------------------
resource "google_service_account" "node_sa" {
  project      = var.project_id
  account_id   = "${var.app_name}-gke-${var.env}-node-sa"
  display_name = "GKE Node SA (${var.app_name}-gke-${var.env})"
}

resource "google_project_iam_member" "node_sa_roles" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.node_sa.member
}

# ------------------------------------------------------------------------------
# App SA — account_id: {app}-sa-{env}
# ------------------------------------------------------------------------------
resource "google_service_account" "app_sa" {
  project      = var.project_id
  account_id   = "${var.app_name}-sa-${var.env}"
  display_name = "${var.app_name} Service Account (${var.env})"
}

# Conditioned cloudsql.client on the deterministic instance name (created in env).
resource "google_project_iam_member" "app_sa_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = google_service_account.app_sa.member

  condition {
    title       = "restrict-to-${local.cloud_sql_instance_name}"
    description = "Allows connection only to the ${local.cloud_sql_instance_name} instance"
    expression  = "resource.name == 'projects/${var.project_id}/instances/${local.cloud_sql_instance_name}' && resource.service == 'sqladmin.googleapis.com'"
  }
}

# ------------------------------------------------------------------------------
# ARC app-runner SA — account_id: github-app-runner-sa-{env}
# ------------------------------------------------------------------------------
resource "google_service_account" "app_runner_sa" {
  project      = var.project_id
  account_id   = "github-app-runner-sa-${var.env}"
  display_name = "GitHub ARC App Runner SA (${var.env})"
}

resource "google_project_iam_member" "app_runner_roles" {
  for_each = local.app_runner_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.app_runner_sa.member
}

# ------------------------------------------------------------------------------
# External Secrets SA — account_id: external-secrets-{env}
# No project roles. Secret Manager access is resource-level, granted by the env apply.
# ------------------------------------------------------------------------------
resource "google_service_account" "external_secrets" {
  project      = var.project_id
  account_id   = "external-secrets-${var.env}"
  display_name = "External Secrets SA (${var.env})"
}

# ------------------------------------------------------------------------------
# D6: resource-level grants for the infra runner (not project-level SA admin/user)
# - infraRunnerWorkloadIdentityAdmin on app, app-runner, and external-secrets (WI policy only)
# - serviceAccountUser on node SA (attach to GKE node pools)
# Runner must not setIamPolicy on terraform-sa, and must not mint keys.
# ------------------------------------------------------------------------------
resource "google_service_account_iam_member" "runner_admin_on_app_sa" {
  service_account_id = google_service_account.app_sa.name
  role               = local.runner_wi_admin_role
  member             = "serviceAccount:${var.runner_sa_email}"

  condition {
    title       = "workload-identity-user-only"
    description = "setIamPolicy may only change roles/iam.workloadIdentityUser"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/iam.workloadIdentityUser'])"
  }
}

resource "google_service_account_iam_member" "runner_admin_on_app_runner_sa" {
  service_account_id = google_service_account.app_runner_sa.name
  role               = local.runner_wi_admin_role
  member             = "serviceAccount:${var.runner_sa_email}"

  condition {
    title       = "workload-identity-user-only"
    description = "setIamPolicy may only change roles/iam.workloadIdentityUser"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/iam.workloadIdentityUser'])"
  }
}

resource "google_service_account_iam_member" "runner_admin_on_external_secrets" {
  service_account_id = google_service_account.external_secrets.name
  role               = local.runner_wi_admin_role
  member             = "serviceAccount:${var.runner_sa_email}"

  condition {
    title       = "workload-identity-user-only"
    description = "setIamPolicy may only change roles/iam.workloadIdentityUser"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly(['roles/iam.workloadIdentityUser'])"
  }
}

resource "google_service_account_iam_member" "runner_user_on_node_sa" {
  service_account_id = google_service_account.node_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.runner_sa_email}"
}
