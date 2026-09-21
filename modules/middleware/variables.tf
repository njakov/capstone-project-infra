variable "allowed_source_ranges" {
  description = "CIDR blocks allowed to reach the Ingress LoadBalancer. Must be set per environment (operator IP/VPN); must not be world-open."
  type        = list(string)

  validation {
    condition = (
      length(var.allowed_source_ranges) > 0 &&
      !contains(var.allowed_source_ranges, "0.0.0.0/0") &&
      !contains(var.allowed_source_ranges, "::/0")
    )
    error_message = "allowed_source_ranges must be a non-empty list and must not include 0.0.0.0/0 or ::/0. Set your operator or VPN CIDR in env tfvars."
  }
}

variable "prometheus_retention" {
  description = "Prometheus TSDB retention period (suitable for a small demo cluster)."
  type        = string
  default     = "7d"
}

variable "prometheus_storage_size" {
  description = "Persistent volume size for Prometheus data."
  type        = string
  default     = "10Gi"
}

variable "grafana_admin_password" {
  description = <<-EOT
    Grafana admin password. When null, kube-prometheus-stack uses its chart default
    (prom-operator). Prefer setting this via TF_VAR_grafana_admin_password from Secret
    Manager or a one-time local secret for demos — do not commit the value.
  EOT
  type        = string
  default     = null
  sensitive   = true
}
