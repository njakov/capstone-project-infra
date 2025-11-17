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

output "db_password_secret_version_id" {
  description = "The ID of the Secret Manager secret containing the DB password."
  value       = google_secret_manager_secret_version.db_password_version.id
}