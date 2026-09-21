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

variable "infra_subnet_cidr" {
  description = "Infra VPC private subnet CIDR for GCE runners (distinct per env)"
  type        = string
}
