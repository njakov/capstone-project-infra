output "peering_a_to_b_name" {
  description = "Name of the A→B peering connection"
  value       = google_compute_network_peering.a_to_b.name
}

output "peering_b_to_a_name" {
  description = "Name of the B→A peering connection"
  value       = google_compute_network_peering.b_to_a.name
}
