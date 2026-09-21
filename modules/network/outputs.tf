# outputs.tf

output "network_id" {
  description = "The self-link of the created VPC"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "The name of the created VPC"
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "The self-link of the created VPC (for peering)"
  value       = google_compute_network.main.self_link
}

output "subnet_id" {
  description = "The self-link of the private subnet"
  value       = google_compute_subnetwork.private.id
}

output "subnet_pods_range" {
  description = "The name of the secondary IP range for GKE pods (null if not configured)"
  value       = var.pods_cidr != null ? "pods" : null
}

output "subnet_services_range" {
  description = "The name of the secondary IP range for GKE services (null if not configured)"
  value       = var.services_cidr != null ? "services" : null
}

output "subnet_ip_cidr_range" {
  description = "The primary IP range of the private subnet."
  value       = google_compute_subnetwork.private.ip_cidr_range
}
