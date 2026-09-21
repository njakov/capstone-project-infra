# Workload Identity bindings only. SAs and project IAM live in bootstrap-iam.
# Do not add project-level IAM member resources here — day-2 runner is not project IAM admin.

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = var.app_sa_email
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_sa_name}]"
}

resource "google_service_account_iam_member" "app_runner_workload_identity" {
  count = var.app_runner_sa_email != "" ? 1 : 0

  service_account_id = var.app_runner_sa_email
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.arc_runners_namespace}/${var.arc_runner_k8s_sa_name}]"
}
