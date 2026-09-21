variable "network_a_self_link" {
  description = "Self-link of the first VPC (e.g. infra)"
  type        = string
}

variable "network_b_self_link" {
  description = "Self-link of the second VPC (e.g. app)"
  type        = string
}

variable "peering_name_a_to_b" {
  description = "Name of the peering connection from network A to B"
  type        = string
}

variable "peering_name_b_to_a" {
  description = "Name of the peering connection from network B to A"
  type        = string
}

variable "export_custom_routes" {
  description = "Export custom routes (needed so peered VPC learns GKE master CIDR routes)"
  type        = bool
  default     = true
}

variable "import_custom_routes" {
  description = "Import custom routes from the peer"
  type        = bool
  default     = true
}
