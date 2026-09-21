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
  description = "Application name used in resource naming"
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

variable "create_app_runner_sa" {
  type        = bool
  description = "Create the least-privilege GCP SA used by ARC ephemeral app runners"
  default     = false
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
