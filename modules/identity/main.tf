resource "google_service_account" "app_sa" {
  project      = var.project_id
  account_id   = "${var.app_name}-sa-${var.env}"
  display_name = "${var.app_name} Service Account (${var.env})"
}

# Bind to Kubernetes Service Account (Workload Identity)
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_sa_name}]"
}

# ------------------------------------------------------------------------------
# ARC app-runner GCP SA (least privilege — no Terraform / network / IAM admin)
# Created here so ARC can bind Workload Identity later; forbidden roles are
# intentionally omitted: projectIamAdmin, networkAdmin, secretmanager.admin,
# storage state admin.
# ------------------------------------------------------------------------------
resource "google_service_account" "app_runner_sa" {
  count = var.create_app_runner_sa ? 1 : 0

  project      = var.project_id
  account_id   = "github-app-runner-sa-${var.env}"
  display_name = "GitHub ARC App Runner SA (${var.env})"
}

locals {
  app_runner_roles = var.create_app_runner_sa ? toset([
    "roles/artifactregistry.writer",
    "roles/container.developer",
  ]) : toset([])
}

resource "google_project_iam_member" "app_runner_permissions" {
  for_each = local.app_runner_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.app_runner_sa[0].email}"
}

resource "google_service_account_iam_member" "app_runner_workload_identity" {
  count = var.create_app_runner_sa ? 1 : 0

  service_account_id = google_service_account.app_runner_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.arc_runners_namespace}/${var.arc_runner_k8s_sa_name}]"
}
