variable "project_id" {
  type        = string
  description = "GCP project ID that holds the GitHub App Secret Manager shells."
}

variable "env" {
  type        = string
  description = "Environment name (dev, prod). Used in the default Secret Manager secret ids."
}

variable "gcp_service_account_email" {
  type        = string
  description = "Email of the bootstrap External Secrets GCP service account. Annotated onto the arc-runners Kubernetes ServiceAccount. The controller ServiceAccount is not given this identity."
}

variable "arc_runners_namespace" {
  type        = string
  description = "Namespace for the External Secrets Kubernetes ServiceAccount, SecretStore, and ExternalSecret. Must already exist (modules/arc)."
  default     = "arc-runners"
}

variable "k8s_service_account_name" {
  type        = string
  description = "Kubernetes ServiceAccount in arc-runners that may assume the External Secrets GCP account. Must match the identity module Workload Identity binding."
  default     = "external-secrets"
}

variable "controller_namespace" {
  type        = string
  description = "Namespace for the External Secrets operator. The controller ServiceAccount in this namespace is not granted Secret Manager access."
  default     = "external-secrets"
}

variable "chart_version" {
  type        = string
  description = "Pinned external-secrets chart version from https://charts.external-secrets.io."
  default     = "2.11.0"
}

variable "github_app_id_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App ID. Null uses arc-github-app-id-<env>, matching modules/arc."
  default     = null
}

variable "github_app_installation_id_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App installation ID. Null uses arc-github-app-installation-id-<env>, matching modules/arc."
  default     = null
}

variable "github_app_private_key_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App private key (PEM). Null uses arc-github-app-private-key-<env>, matching modules/arc."
  default     = null
}
