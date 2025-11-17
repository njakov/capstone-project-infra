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