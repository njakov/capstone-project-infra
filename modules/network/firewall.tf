resource "google_compute_firewall" "allow_iap_ssh" {
  project = var.project_id
  name    = "${var.network_name}-allow-iap-ssh"
  network = google_compute_network.main.name

  description = "Allows SSH (TCP/22) access ONLY from IAP range."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # This specific IP range is owned by Google IAP. 
  # tfsec:ignore:google-compute-no-public-ingress
  source_ranges = ["35.235.240.0/20"]
}