# 1. Create the VPC
resource "google_compute_network" "main" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
}

# 2. Create the private subnet (optional GKE secondary ranges)
resource "google_compute_subnetwork" "private" {
  project       = var.project_id
  name          = "${var.network_name}-private"
  ip_cidr_range = var.subnet_cidr

  region                   = var.region
  network                  = google_compute_network.main.id
  private_ip_google_access = true # Crucial for GKE and internal services

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  dynamic "secondary_ip_range" {
    for_each = var.pods_cidr != null ? [var.pods_cidr] : []
    content {
      range_name    = "pods"
      ip_cidr_range = secondary_ip_range.value
    }
  }

  dynamic "secondary_ip_range" {
    for_each = var.services_cidr != null ? [var.services_cidr] : []
    content {
      range_name    = "services"
      ip_cidr_range = secondary_ip_range.value
    }
  }
}

# 3. Create a Cloud Router (required for NAT)
resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

# 4. Create the Cloud NAT gateway
resource "google_compute_router_nat" "nat" {
  project                            = var.project_id
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
