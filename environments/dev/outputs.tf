output "artifact_registry_url" {
  description = "The URL for the Docker Artifact Registry"
  value       = module.artifact_registry.repo_url
}