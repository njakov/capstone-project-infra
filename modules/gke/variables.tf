# modules/gke/variables.tf

variable "project_id" {
  type        = string
  description = "The GCP project ID."
}

variable "cluster_location" {
  type        = string
  description = "GKE control-plane location: a region (regional HA) or a zone (zonal). Must match both node pools."
}

variable "node_locations" {
  type        = list(string)
  description = "Zones where worker nodes may run. For a zonal cluster, typically a single zone matching cluster_location."
}

variable "cluster_name" {
  type        = string
  description = "The name for the GKE cluster."
}

variable "node_service_account_email" {
  type        = string
  description = "Email of the pre-created GKE node service account (from bootstrap-iam)."
}

variable "network_name" {
  type        = string
  description = "The name of the VPC network to deploy GKE into."
}

variable "subnet_id" {
  type        = string
  description = "The self-link of the GKE subnet."
}

variable "subnet_pods_range" {
  type        = string
  description = "The name of the secondary range for Pods."
}

variable "subnet_services_range" {
  type        = string
  description = "The name of the secondary range for Services."
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "The /28 CIDR block for the GKE Control Plane. Must not overlap with any subnet ranges, and must be unique per cluster when multiple clusters share one GCP project."
  default     = "172.16.0.0/28"
}

variable "min_node_count" {
  type        = number
  description = "Minimum nodes per zone in the primary pool (google_container_node_pool autoscaling is per zone)."
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum nodes per zone in the primary pool for autoscaling (per zone, not cluster-wide)."
  default     = 3
}

variable "max_surge" {
  description = "The number of additional nodes that can be added to the node pool during an upgrade."
  type        = number
  default     = 1
}

variable "max_unavailable" {
  description = "The number of nodes that can be simultaneously unavailable during an upgrade."
  type        = number
  default     = 0
}

variable "subnet_ip_cidr_range" {
  type        = string
  description = "The primary IP range of the app subnet (for master authorized networks)."
}

variable "additional_master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "Extra CIDRs allowed to reach the private GKE control plane (e.g. infra runner subnet)."
  default     = []
}

variable "node_pool_name" {
  type        = string
  description = "The name of the node pool."
  default     = "primary-pool"
}

variable "machine_type" {
  type        = string
  description = "The machine type for the node pool."
  default     = "e2-standard-2"
}

variable "disk_type" {
  type        = string
  description = "Type of the disk attached to each node (e.g., 'pd-standard', 'pd-balanced' or 'pd-ssd')."
  default     = "pd-balanced"
}

variable "disk_size_gb" {
  type        = number
  description = "Size of the disk attached to each node, specified in GB."
  default     = 50
}

variable "image_type" {
  type        = string
  description = "The image type to use for the nodes. COS_CONTAINERD is recommended for security."
  default     = "COS_CONTAINERD"
}

variable "auto_repair" {
  type        = bool
  description = "Whether the nodes will be automatically repaired."
  default     = true
}

variable "auto_upgrade" {
  type        = bool
  description = "Whether the nodes will be automatically upgraded."
  default     = true
}

variable "maintenance_start_time" {
  description = "Time window specified for daily maintenance operations in UTC"
  type        = string
  default     = "03:00"
}

variable "labels" {
  type        = map(string)
  description = "GCP labels to apply to the cluster for billing and organization."
  default = {
    terraform = "true"
  }
}

variable "node_tags" {
  type        = list(string)
  description = "List of network tags applied to the nodes."
  default     = []
}

variable "enable_secure_boot" {
  type        = bool
  description = "Secure Boot helps ensure that the system only runs authentic software by verifying the digital signature of all boot components."
  default     = true
}

variable "enable_integrity_monitoring" {
  type        = bool
  description = "Enables monitoring and attestation of the boot integrity of the instance. The attestation is performed against the integrity policy baseline."
  default     = true
}

# ------------------------------------------------------------------------------
# Dedicated ARC / GitHub runner node pool
# ------------------------------------------------------------------------------

variable "enable_runner_node_pool" {
  type        = bool
  description = "Create a tainted node pool reserved for ARC ephemeral runners."
  default     = true
}

variable "runner_node_pool_name" {
  type        = string
  description = "Name of the ARC runner node pool."
  default     = "runners"
}

variable "runner_machine_type" {
  type        = string
  description = "Machine type for ARC runner nodes (Kaniko builds need more CPU/memory than app nodes)."
  default     = "e2-standard-4"
}

variable "runner_min_node_count" {
  type        = number
  description = "Minimum nodes per zone in the runner pool (0 allows scale-to-zero; per zone)."
  default     = 0
}

variable "runner_max_node_count" {
  type        = number
  description = "Maximum nodes per zone in the runner pool."
  default     = 2
}

variable "runner_disk_size_gb" {
  type        = number
  description = "Boot disk size for runner nodes in GB."
  default     = 50
}

variable "runner_image_type" {
  type        = string
  description = "Image type for runner nodes. COS_CONTAINERD is preferred for non-privileged Kaniko builds."
  default     = "COS_CONTAINERD"
}