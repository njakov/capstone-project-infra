# environments/dev/backend.tf
terraform {
  backend "gcs" {
    prefix = "env/dev"
  }
}