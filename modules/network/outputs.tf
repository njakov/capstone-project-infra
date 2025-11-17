# outputs.tf

output "network_id" {
  description = "The self-link of the created VPC"
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "The name of the created VPC"
  value       = google_compute_network.main.name
}

output "subnet_id" {
  description = "The self-link of the private subnet"
  value       = google_compute_subnetwork.private.id
}

output "subnet_pods_range" {
  description = "The name of the secondary IP range for GKE pods"
  value       = google_compute_subnetwork.private.secondary_ip_range[0].range_name
}

output "subnet_services_range" {
  description = "The name of the secondary IP range for GKE services"
  value       = google_compute_subnetwork.private.secondary_ip_range[1].range_name
}

output "subnet_ip_cidr_range" {
  description = "The primary IP range of the private subnet."
  value       = google_compute_subnetwork.private.ip_cidr_range
}