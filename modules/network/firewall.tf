resource "google_compute_firewall" "allow_iap_ssh" {
  count = length(var.iap_ssh_target_tags) > 0 ? 1 : 0

  project = var.project_id
  name    = "${var.network_name}-allow-iap-ssh"
  network = google_compute_network.main.name

  description = "Allows SSH (TCP/22) access ONLY from IAP range, scoped to tagged VMs."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google IAP's published range. The rule is limited to target_tags, so it is
  # not open ingress. Trivy only flags 0.0.0.0/0 when no tags are set.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = var.iap_ssh_target_tags
}
