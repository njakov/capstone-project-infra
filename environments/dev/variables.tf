# environments/dev/variables.tf

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "app_name" {
  description = "Short name of the application (used in resource names)"
  type        = string
}

variable "env" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "gke_min_nodes" {
  type        = number
  description = "Minimum GKE nodes per zone in the primary pool."
  default     = 1
}

variable "gke_max_nodes" {
  type        = number
  description = "Maximum GKE nodes per zone in the primary pool."
  default     = 3
}

variable "gke_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "gke_cluster_location" {
  type        = string
  description = "GKE control-plane location: zone (zonal) or region (regional HA)."
}

variable "gke_node_locations" {
  type        = list(string)
  description = "Zones where GKE worker nodes may run (per-zone min/max apply)."
}

variable "db_tier" {
  description = "Database instance machine type"
  type        = string
}

variable "db_availability_type" {
  description = "Cloud SQL availability: ZONAL or REGIONAL"
  type        = string
}

variable "gke_maintenance_start_time" {
  description = "Time window specified for daily maintenance operations in UTC"
  type        = string
  default     = "03:00"
}

variable "master_ipv4_cidr_block" {
  description = "GKE control-plane /28 CIDR. Must be unique per cluster in this project (dev vs prod)."
  type        = string
}

variable "subnet_cidr" {
  description = "App VPC private subnet CIDR"
  type        = string
}

variable "pods_cidr" {
  description = "App VPC secondary range for GKE pods"
  type        = string
}

variable "services_cidr" {
  description = "App VPC secondary range for GKE services"
  type        = string
}

variable "allowed_source_ranges" {
  description = "CIDR blocks allowed to reach the Ingress LoadBalancer (operator IP/VPN). Not world-open."
  type        = list(string)
}

variable "grafana_admin_password" {
  description = "Optional Grafana admin password for kube-prometheus-stack. Null keeps chart default (prom-operator). Prefer TF_VAR / Secret Manager — do not commit."
  type        = string
  default     = null
  sensitive   = true
}

variable "deletion_protection" {
  description = "When true, GKE and Cloud SQL cannot be destroyed. Set false in tfvars and apply before an intentional destroy."
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# GKE runner node pool (ARC)
# ------------------------------------------------------------------------------
variable "gke_runner_machine_type" {
  type        = string
  description = "Machine type for the tainted ARC runner node pool."
  default     = "e2-standard-4"
}

variable "gke_runner_min_nodes" {
  type        = number
  description = "Minimum nodes in the ARC runner pool (0 = scale-to-zero)."
  default     = 0
}

variable "gke_runner_max_nodes" {
  type        = number
  description = "Maximum nodes in the ARC runner pool."
  default     = 2
}

# ------------------------------------------------------------------------------
# ARC (Actions Runner Controller)
# ------------------------------------------------------------------------------
variable "enable_arc" {
  type        = bool
  description = "Provision ARC Secret Manager shells (and charts when arc_install_charts is true)."
  default     = true
}

variable "arc_install_charts" {
  type        = bool
  description = "Install ARC Helm releases. Keep false until GitHub App secret versions exist and ExternalSecret arc-github-app in arc-runners is Ready (see docs/arc-cutover.md)."
  default     = false
}

variable "arc_github_config_url" {
  type        = string
  description = "GitHub URL the ARC scale set registers against (app repo)."
  default     = "https://github.com/njakov/capstone-project-app"
}

variable "arc_min_runners" {
  type        = number
  description = "Minimum idle ARC runners."
  default     = 0
}

variable "arc_max_runners" {
  type        = number
  description = "Maximum concurrent ARC runners."
  default     = 3
}
