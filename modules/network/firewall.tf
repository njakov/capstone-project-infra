resource "google_compute_firewall" "allow_internal_strict" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal-strict"
  network = google_compute_network.main.name

  description = "Allows (TCP/UDP/ICMP) protocols for Ingress traffic between subnets within this VPC."

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr, # Nodes & Runner
    var.pods_cidr    # GKE Pods
  ]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

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