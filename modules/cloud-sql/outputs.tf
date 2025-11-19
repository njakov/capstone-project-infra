# modules/cloud-sql/outputs.tf

output "instance_connection_name" {
  description = "The connection name for the Cloud SQL instance (project:region:instance)."
  value       = google_sql_database_instance.main.connection_name
}

output "db_name" {
  description = "The name of the database."
  value       = google_sql_database.database.name
}

output "db_user" {
  description = "The name of the application user."
  value       = google_sql_user.user.name
}

output "private_ip_address" {
  description = "The private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "db_password_plain" {
  description = "The application user's plain text password."
  value       = random_password.db_password.result
  sensitive   = true # Mark as sensitive to prevent logging in plaintext
}