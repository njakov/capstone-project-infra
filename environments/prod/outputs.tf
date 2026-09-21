output "artifact_registry_url" {
  description = "The URL for the Docker Artifact Registry"
  value       = module.artifact_registry.repo_url
}

output "app_sa_email" {
  description = "App Workload Identity GCP SA email (for docs / local Helm --set)."
  value       = module.identity.email
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)."
  value       = module.cloud_sql.instance_connection_name
}

output "arc_runner_scale_set_name" {
  description = "ARC scale set name for app workflow runs-on (null if ARC disabled)."
  value       = var.enable_arc ? module.arc[0].runner_scale_set_name : null
}

output "arc_github_app_secret_ids" {
  description = "Secret Manager ids to populate before arc_install_charts = true."
  value       = var.enable_arc ? module.arc[0].github_app_secret_ids : null
}

output "arc_charts_installed" {
  description = "Whether ARC Helm charts are installed in this environment."
  value       = var.enable_arc ? module.arc[0].charts_installed : false
}
