# environments/prod/backend.tf
terraform {
  backend "gcs" {
    prefix = "env/prod"
  }
}