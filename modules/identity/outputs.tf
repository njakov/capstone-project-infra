output "email" {
  description = "Email of the application GCP service account"
  value       = var.app_sa_email
}

output "app_runner_email" {
  description = "Email of the ARC app-runner GCP service account (empty string if not bound)"
  value       = var.app_runner_sa_email
}
