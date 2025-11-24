# environments/bootstrap/variables.tf

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