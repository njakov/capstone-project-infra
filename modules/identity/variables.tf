variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "app_sa_email" {
  type        = string
  description = "Email of the pre-created application GCP service account (from bootstrap-iam)."
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace for the app Workload Identity binding (must match Helm --namespace)"
  default     = "petclinic"
}

variable "k8s_sa_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for the app"
}

variable "app_runner_sa_email" {
  type        = string
  description = "Email of the pre-created ARC app-runner GCP SA. Empty string skips the WI binding."
  default     = ""
}

variable "arc_runners_namespace" {
  type        = string
  description = "Namespace where ARC runner pods run (WI binding target)"
  default     = "arc-runners"
}

variable "arc_runner_k8s_sa_name" {
  type        = string
  description = "Kubernetes ServiceAccount name used by ARC runner pods"
  default     = "arc-runner"
}
