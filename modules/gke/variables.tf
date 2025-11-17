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

# --- Network Inputs (from your network module) ---

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

# --- Node Pool Inputs ---

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