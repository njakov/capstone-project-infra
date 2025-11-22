# modules/gke/node_pools.tf

resource "google_container_node_pool" "primary_nodes" {
  project            = var.project_id
  name               = "primary-pool"
  location           = var.region
  cluster            = google_container_cluster.primary.id
  initial_node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.machine_type
    disk_type    = var.disk_type
    disk_size_gb = var.disk_size_gb

    image_type = "COS_CONTAINERD"

    service_account = google_service_account.gke_node_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      "node-pool" = "primary"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}