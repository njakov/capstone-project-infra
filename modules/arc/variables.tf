variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "env" {
  type        = string
  description = "Environment name (dev, prod)."
}

variable "app_name" {
  type        = string
  description = "Application short name (used in scale set naming)."
}

variable "github_config_url" {
  type        = string
  description = "GitHub URL for the runner scale set (repo, org, or enterprise). Example: https://github.com/njakov/capstone-project-app"
}

variable "app_runner_gcp_sa_email" {
  type        = string
  description = "Email of the least-privilege GCP SA used by ARC runner pods (Workload Identity)."
}

variable "external_secrets_gcp_sa_email" {
  type        = string
  description = "Email of the External Secrets GCP SA granted secretAccessor on the three GitHub App Secret Manager shells."
}

variable "arc_systems_namespace" {
  type        = string
  description = "Namespace for the ARC controller."
  default     = "arc-systems"
}

variable "arc_runners_namespace" {
  type        = string
  description = "Namespace for ephemeral runner pods."
  default     = "arc-runners"
}

variable "runner_k8s_sa_name" {
  type        = string
  description = "Kubernetes ServiceAccount name for ARC runner pods (must match identity WI binding)."
  default     = "arc-runner"
}

variable "runner_scale_set_name" {
  type        = string
  description = "ARC scale set name — becomes the GitHub Actions runs-on label."
  default     = null
}

variable "min_runners" {
  type        = number
  description = "Minimum idle runners (0 = scale to zero)."
  default     = 0
}

variable "max_runners" {
  type        = number
  description = "Maximum concurrent runners."
  default     = 3
}

variable "chart_version" {
  type        = string
  description = "Pinned version for gha-runner-scale-set-controller and gha-runner-scale-set charts."
  default     = "0.10.1"
}

variable "runner_node_selector" {
  type        = map(string)
  description = "nodeSelector applied to ephemeral runner pods."
  default = {
    workload = "github-runner"
  }
}

variable "runner_tolerations" {
  type = list(object({
    key      = string
    operator = string
    value    = string
    effect   = string
  }))
  description = "Tolerations so runner pods can schedule on the tainted runners pool."
  default = [
    {
      key      = "github.runner"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
}

variable "install_charts" {
  type        = bool
  description = "Install ARC Helm releases and NetworkPolicies. Set false on first apply to create Secret Manager shells and the arc-runners namespace. Flip true only after ExternalSecret arc-github-app is Ready."
  default     = true
}

variable "github_app_id_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App ID (created by this module if missing)."
  default     = null
}

variable "github_app_installation_id_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App installation ID."
  default     = null
}

variable "github_app_private_key_secret_id" {
  type        = string
  description = "Secret Manager secret id for the GitHub App private key (PEM)."
  default     = null
}
