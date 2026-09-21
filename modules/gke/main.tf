# modules/gke/main.tf
# Node SA is created in bootstrap-iam; this module only attaches it to node pools.

# tfsec:ignore:google-gke-enable-network-policy
# tfsec:ignore:google-gke-enforce-pod-security-policy
resource "google_container_cluster" "primary" {
  project             = var.project_id
  name                = var.cluster_name
  location            = var.cluster_location
  node_locations      = var.node_locations
  networking_mode     = "VPC_NATIVE"
  network             = var.network_name
  subnetwork          = var.subnet_id
  deletion_protection = false

  ip_allocation_policy {
    cluster_secondary_range_name  = var.subnet_pods_range
    services_secondary_range_name = var.subnet_services_range
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # Peering is not transitive, and Regular-channel control planes use PSC, so
  # Terraform uses this DNS name instead of the private IP.
  # allow_external_traffic has no network allowlist: the name is reachable from
  # any network that can reach Google APIs. Master authorized networks apply
  # only to the IP endpoint. Callers still need container.clusters.connect.
  # Kubernetes ServiceAccount tokens and client certs stay disabled on this name.
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic    = true
      enable_k8s_tokens_via_dns = false
      enable_k8s_certs_via_dns  = false
    }
  }

  master_authorized_networks_config {
    cidr_blocks {
      display_name = "app-private-subnet"
      cidr_block   = var.subnet_ip_cidr_range
    }

    dynamic "cidr_blocks" {
      for_each = var.additional_master_authorized_networks
      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
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

  timeouts {
    create = "60m"
  }
}
