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