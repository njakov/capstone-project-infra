# modules/gke/variables.tf

variable "project_id" {
  type        = string
  description = "The GCP project ID."
}

variable "region" {
  type        = string
  description = "The region for the GKE cluster (e.g., 'europe-west1')."
}

variable "cluster_name" {
  type        = string
  description = "The name for the GKE cluster."
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
  description = "The /28 CIDR block for the GKE Control Plane. Must not overlap with any subnet ranges."
  default     = "172.16.0.0/28"
}

variable "min_node_count" {
  type        = number
  description = "Minimum number of nodes in the pool."
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum number of nodes in the pool for autoscaling."
  default     = 3
}

variable "subnet_ip_cidr_range" {
  type        = string
  description = "The primary IP range of the subnet (for master authorized networks)."
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
    environment = "dev"
    terraform   = "true"
    app         = "petclinic"
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