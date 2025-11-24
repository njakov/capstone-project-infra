variable "allowed_source_ranges" {
  description = "List of CIDR blocks allowed to access the Ingress Load Balancer"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}