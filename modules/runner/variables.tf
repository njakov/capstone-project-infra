variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "env" {
  description = "The environment name (e.g., dev, prod) used for naming resources"
  type        = string
}

variable "zone" {
  description = "The GCP zone to deploy the runner into (e.g., europe-west1-b)"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type for the infra Terraform runner (no Docker builds)"
  type        = string
  default     = "e2-medium"
}

variable "network_name" {
  description = "The name of the VPC network where the runner will be placed"
  type        = string
}

variable "subnet_id" {
  description = "The ID (self_link) of the private subnet where the runner will be placed"
  type        = string
}

variable "disk_kms_key_id" {
  description = "Full id of the Cloud KMS key that encrypts the runner boot disk. create-bucket.sh creates runner-disk-key."
  type        = string
}