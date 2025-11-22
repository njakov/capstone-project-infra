# modules/gke/outputs.tf

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_location" {
  description = "The location (region) of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "workload_identity_pool" {
  description = "The workload identity pool for the cluster."
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool
}

output "cluster_endpoint" {
  description = "The IP address of the cluster master."
  sensitive   = true
  value       = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The public certificate that is the root of trust for the cluster."
  sensitive   = true
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}

output "node_service_account_email" {
  description = "The email of the Service Account used by the GKE nodes."
  value       = google_service_account.gke_node_sa.email
}