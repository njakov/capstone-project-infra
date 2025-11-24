# variables.tf

variable "project_id" {
  type        = string
  description = "The GCP project ID"
}

variable "region" {
  type        = string
  description = "The region to deploy resources in"
}

variable "network_name" {
  type        = string
  default     = "petclinic-vpc"
  description = "The name for the main VPC"
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