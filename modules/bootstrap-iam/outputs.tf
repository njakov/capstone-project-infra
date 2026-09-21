output "node_sa_email" {
  description = "Email of the GKE node service account"
  value       = google_service_account.node_sa.email
}

output "app_sa_email" {
  description = "Email of the application service account"
  value       = google_service_account.app_sa.email
}

output "app_runner_sa_email" {
  description = "Email of the ARC app-runner service account"
  value       = google_service_account.app_runner_sa.email
}

output "external_secrets_sa_email" {
  description = "Email of the External Secrets service account"
  value       = google_service_account.external_secrets.email
}

output "cloud_sql_instance_name" {
  description = "Deterministic Cloud SQL instance name used in the cloudsql.client IAM condition"
  value       = local.cloud_sql_instance_name
}
