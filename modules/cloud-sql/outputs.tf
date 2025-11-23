# modules/cloud-sql/outputs.tf

output "instance_connection_name" {
  description = "The connection name for the Cloud SQL instance (project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "The private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "db_username_secret_id" {
  description = "The Secret Manager ID for the database username"
  value       = google_secret_manager_secret.db_username.secret_id
}

output "db_password_secret_id" {
  description = "The Secret Manager ID for the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_url_secret_id" {
  description = "The Secret Manager ID for the JDBC URL"
  value       = google_secret_manager_secret.db_url.secret_id
}