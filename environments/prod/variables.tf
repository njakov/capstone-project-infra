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
  type    = number
  default = 1
}

variable "gke_max_nodes" {
  type    = number
  default = 3
}

variable "gke_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "db_tier" {
  description = "Database instance machine type"
  type        = string
}

variable "gke_maintenance_start_time" {
  description = "Time window specified for daily maintenance operations in UTC"
  type        = string
  default     = "03:00"
}

variable "allowed_source_ranges" {
  description = "List of IP CIDR blocks allowed to access the Load Balancer"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Default to open if not specified
}

variable "subnet_cidr" {
  description = "The IP range for the private subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "pods_cidr" {
  description = "The secondary IP range for Pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "The secondary IP range for Services"
  type        = string
  default     = "10.30.0.0/16"
}