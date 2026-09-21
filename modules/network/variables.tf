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
  description = "Secondary IP range for GKE pods. Set to null to skip (infra VPCs)."
  type        = string
  default     = "10.20.0.0/16"
  nullable    = true
}

variable "services_cidr" {
  description = "Secondary IP range for GKE services. Set to null to skip (infra VPCs)."
  type        = string
  default     = "10.30.0.0/16"
  nullable    = true
}

variable "iap_ssh_target_tags" {
  description = "If non-empty, create an IAP SSH firewall rule targeting only these network tags."
  type        = list(string)
  default     = []
}
