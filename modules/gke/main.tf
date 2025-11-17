# modules/gke/main.tf

# --- Best Practice: Dedicated, Least-Privilege SA for GKE Nodes ---
resource "google_service_account" "gke_node_sa" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node SA for ${var.cluster_name}"
}

# Grant nodes the basic roles needed to write logs/metrics and pull images
resource "google_project_iam_member" "node_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.gke_node_sa.member
}

resource "google_project_iam_member" "node_sa_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = google_service_account.gke_node_sa.member
}

resource "google_project_iam_member" "node_sa_image_puller" {
  project = var.project_id
  role    = "roles/storage.objectViewer" # Allows pulling from GCR/GAR
  member  = google_service_account.gke_node_sa.member
}

# --- The GKE Cluster Resource ---
resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.region # This makes it a Regional cluster (High Availability)

  # Best Practice: Remove the default (unmanaged) node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # Connect it to the network you built
  network    = var.network_name
  subnetwork = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.subnet_pods_range
    services_secondary_range_name = var.subnet_services_range
  }

  # --- Best Practice: Security Configuration ---

  # 1. Make it a private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true # No public control plane endpoint
    master_ipv4_cidr_block  = "172.16.0.0/28" # Small, internal-only range
  }

    master_authorized_networks_config {
        cidr_blocks {
        display_name = "private-subnet"
        cidr_block   = var.subnet_ip_cidr_range
        }
    }

  # 2. Enable Workload Identity (for secure pod-to-GCP auth)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # 3. Enable managed, auto-upgrading release channels
  release_channel {
    channel = "REGULAR"
  }

  # 4. Enable Network Policy (for pod-to-pod firewall rules)
  network_policy {
    enabled = true
  }
}

# --- Best Practice: Managed, Autoscaling Node Pool ---
resource "google_container_node_pool" "primary_nodes" {
  project    = var.project_id
  name       = "default-pool"
  cluster    = google_container_cluster.primary.id
  location   = var.region
  node_count = var.min_node_count

  # Autoscaling configuration
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  # Node configuration
  node_config {
    machine_type = "e2-medium" # Good, cost-effective default

    # Use the dedicated SA you created
    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}