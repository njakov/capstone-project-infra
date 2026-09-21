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
  description = "App VPC private subnet CIDR (distinct per env in this project)"
  type        = string
}

variable "pods_cidr" {
  description = "App VPC secondary range for GKE pods"
  type        = string
}

variable "services_cidr" {
  description = "App VPC secondary range for GKE services"
  type        = string
}

variable "infra_subnet_cidr" {
  description = "Infra VPC private subnet CIDR for GCE runners (distinct per env)"
  type        = string
}
