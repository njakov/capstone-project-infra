output "repo_url" {
  description = "The URL of the repository (e.g., europe-west1-docker.pkg.dev/project-id/repo-name)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.repo.repository_id}"
}