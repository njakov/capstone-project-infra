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