output "email" {
  description = "Email of the application GCP service account"
  value       = google_service_account.app_sa.email
}

output "app_runner_email" {
  description = "Email of the ARC app-runner GCP service account (empty string if not created)"
  value       = try(google_service_account.app_runner_sa[0].email, "")
}
