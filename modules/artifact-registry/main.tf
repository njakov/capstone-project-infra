resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for Capstone Project"
  format        = "DOCKER"
}

# Day-2 runner has roles/artifactregistry.admin, so the env apply can create this.
# The project-level writer binding in bootstrap-iam stays until this exists.
resource "google_artifact_registry_repository_iam_member" "app_runner_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.repository_id
  role       = "roles/artifactregistry.writer"
  member     = var.writer_member
}