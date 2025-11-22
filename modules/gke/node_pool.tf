# modules/gke/node_pools.tf

resource "google_container_node_pool" "primary_nodes" {
  project            = var.project_id
  name               = var.node_pool_name
  location           = var.region
  cluster            = google_container_cluster.primary.id
  initial_node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = var.auto_repair
    auto_upgrade = var.auto_upgrade
  }

  node_config {
    machine_type = var.machine_type
    disk_type    = var.disk_type
    disk_size_gb = var.disk_size_gb
    tags         = var.node_tags
    image_type   = var.image_type

    service_account = google_service_account.gke_node_sa.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = var.enable_secure_boot
      enable_integrity_monitoring = var.enable_integrity_monitoring
    }

    labels = {
      "node-pool" = "primary"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}