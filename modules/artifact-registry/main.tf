resource "google_artifact_registry_repository" "repo" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Docker repository for Capstone Project"
  format        = "DOCKER"
}

# Day-2 runner has roles/artifactregistry.admin, so the env apply can create these.
# These are the only Artifact Registry grants for the app-runner and node SAs.
resource "google_artifact_registry_repository_iam_member" "app_runner_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.repository_id
  role       = "roles/artifactregistry.writer"
  member     = var.writer_member
}

resource "google_artifact_registry_repository_iam_member" "node_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.repo.location
  repository = google_artifact_registry_repository.repo.repository_id
  role       = "roles/artifactregistry.reader"
  member     = var.reader_member
}