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
