# Bidirectional VPC peering so infra runners can reach the private GKE API
# over custom routes exported from the app VPC.

resource "google_compute_network_peering" "a_to_b" {
  name         = var.peering_name_a_to_b
  network      = var.network_a_self_link
  peer_network = var.network_b_self_link

  export_custom_routes                = var.export_custom_routes
  import_custom_routes                = var.import_custom_routes
  export_subnet_routes_with_public_ip = false
  import_subnet_routes_with_public_ip = false
}

resource "google_compute_network_peering" "b_to_a" {
  name         = var.peering_name_b_to_a
  network      = var.network_b_self_link
  peer_network = var.network_a_self_link

  export_custom_routes                = var.export_custom_routes
  import_custom_routes                = var.import_custom_routes
  export_subnet_routes_with_public_ip = false
  import_subnet_routes_with_public_ip = false

  depends_on = [google_compute_network_peering.a_to_b]
}
