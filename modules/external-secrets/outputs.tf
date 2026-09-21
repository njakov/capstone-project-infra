output "controller_namespace" {
  description = "Namespace where the External Secrets operator runs."
  value       = var.controller_namespace
}

output "k8s_service_account_name" {
  description = "Kubernetes ServiceAccount in arc-runners annotated with the External Secrets GCP account."
  value       = kubernetes_service_account_v1.external_secrets.metadata[0].name
}

output "external_secret_name" {
  description = "ExternalSecret name in arc-runners. Ready means secret arc-github-app has been synced."
  value       = local.external_secret_name
}

output "target_secret_name" {
  description = "Kubernetes secret created by the ExternalSecret for the ARC listener."
  value       = local.target_secret_name
}

output "github_app_secret_ids" {
  description = "Secret Manager secret ids synced into arc-github-app."
  value = {
    app_id          = local.github_app_id_secret_id
    installation_id = local.github_app_installation_id_secret_id
    private_key     = local.github_app_private_key_secret_id
  }
}
