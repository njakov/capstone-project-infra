output "runner_scale_set_name" {
  description = "ARC scale set name used as the GitHub Actions runs-on label."
  value       = local.scale_set_name
}

output "arc_runners_namespace" {
  description = "Namespace where ephemeral runner pods run (null until install_charts)."
  value       = var.install_charts ? kubernetes_namespace_v1.arc_runners[0].metadata[0].name : null
}

output "arc_systems_namespace" {
  description = "Namespace where the ARC controller runs (null until install_charts)."
  value       = var.install_charts ? kubernetes_namespace_v1.arc_systems[0].metadata[0].name : null
}

output "runner_k8s_sa_name" {
  description = "Kubernetes ServiceAccount used by ARC runner pods (null until install_charts)."
  value       = var.install_charts ? kubernetes_service_account_v1.arc_runner[0].metadata[0].name : null
}

output "charts_installed" {
  description = "Whether ARC Helm releases and NetworkPolicies are installed."
  value       = var.install_charts
}

output "github_app_secret_ids" {
  description = "Secret Manager secret ids that must have versions before install_charts = true."
  value = {
    app_id          = google_secret_manager_secret.github_app_id.secret_id
    installation_id = google_secret_manager_secret.github_app_installation_id.secret_id
    private_key     = google_secret_manager_secret.github_app_private_key.secret_id
  }
}
