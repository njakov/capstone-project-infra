variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "env" {
  type        = string
  description = "Environment name (dev, prod)"
}

variable "app_name" {
  type        = string
  description = "Application name used in resource naming (must match env Cloud SQL / GKE naming)"
}

variable "runner_sa_email" {
  type        = string
  description = "Email of the infra runner SA (from module.runner) for D6 resource-level grants"
}
