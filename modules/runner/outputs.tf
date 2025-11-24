output "runner_instance_name" {
  description = "The name of the runner VM instance"
  value       = google_compute_instance.runner.name
}

output "runner_instance_zone" {
  description = "The zone of the runner VM instance"
  value       = google_compute_instance.runner.zone
}

output "service_account_email" {
  description = "The email of the service account attached to the runner"
  value       = google_service_account.runner_sa.email
}

output "ssh_command" {
  description = "Run this command to connect to the private runner via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.runner.name} --project ${var.project_id} --zone ${google_compute_instance.runner.zone} --tunnel-through-iap"
}