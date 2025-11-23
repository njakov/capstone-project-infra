# modules/cloud-sql/variables.tf

variable "project_id" {
  type        = string
  description = "The GCP project ID."
}

variable "region" {
  type        = string
  description = "The region for the Cloud SQL instance."
}

variable "environment" {
  type        = string
  description = "The environment name (e.g., dev, prod)."
}

variable "network_name" {
  type        = string
  description = "The name of the VPC network to connect to."
}

variable "db_instance_name" {
  type        = string
  description = "The name for the Cloud SQL instance."
}

variable "db_name" {
  type        = string
  description = "The name of the database to create."
}

variable "db_user" {
  type        = string
  description = "The name of the user for the application."
}

variable "db_tier" {
  type        = string
  description = "The machine type for the instance."
  default     = "db-f1-micro"
  # NOTE: For HA (regional), you must use 'db-g1-small' or larger.
}

variable "app_service_account_email" {
  type        = string
  description = "The email of the application service account to grant secret access to."
}
