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
  type        = string
  description = "The application name, used for naming resources."
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