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

variable "network_name" {
  description = "The name of the VPC network where the runner will be placed"
  type        = string
}

variable "subnet_id" {
  description = "The ID (self_link) of the private subnet where the runner will be placed"
  type        = string
}