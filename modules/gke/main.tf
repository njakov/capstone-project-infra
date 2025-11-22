# modules/gke/main.tf

resource "google_service_account" "gke_node_sa" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node SA for ${var.cluster_name}"
}

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

resource "google_project_iam_member" "node_sa_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = google_service_account.gke_node_sa.member
}

# --- The GKE Cluster Resource ---
# tfsec:ignore:google-gke-enable-network-policy
# tfsec:ignore:google-gke-enforce-pod-security-policy
resource "google_container_cluster" "primary" {
  project         = var.project_id
  name            = var.cluster_name
  location        = var.region
  networking_mode = "VPC_NATIVE"
  network         = var.network_name
  subnetwork      = var.subnet_id

  ip_allocation_policy {
    cluster_secondary_range_name  = var.subnet_pods_range
    services_secondary_range_name = var.subnet_services_range
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    cidr_blocks {
      display_name = "private-subnet"
      cidr_block   = var.subnet_ip_cidr_range
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }
  #GKE Dataplane V2 comes with Kubernetes network policy enforcement built-in
  datapath_provider = "ADVANCED_DATAPATH"

  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = var.labels

  secret_manager_config {
    enabled = true
  }

}
