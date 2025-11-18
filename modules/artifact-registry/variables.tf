variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region to create the repository in"
  type        = string
}

variable "repository_id" {
  description = "The name of the repository (e.g., petclinic-repo)"
  type        = string
}