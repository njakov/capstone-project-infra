# modules/cloud-sql/main.tf

# --- 1. Enable the Service Networking API ---
resource "google_project_service" "service_networking" {
  project                    = var.project_id
  service                    = "servicenetworking.googleapis.com"
  disable_dependent_services = false
}

# --- 2. Create a Private IP Range for the Peering ---
resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "sql-private-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  ip_version    = "IPV4"
  prefix_length = 24
  network       = "projects/${var.project_id}/global/networks/${var.network_name}"
}

# --- 3. Create the VPC Peering Connection ---
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/${var.network_name}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.service_networking]
}

# --- 4. Generate a Random Password ---
resource "random_password" "db_password" {
  length  = 16
  special = false
  keepers = {
    # Changing this value forces a new password to be generated.
    # Use today's date or any random string.
    rotation_trigger = "rotate-2025-11-18"
  }
}

# --- 6. The Cloud SQL Instance ---
resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = var.db_instance_name
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = true

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/${var.network_name}"
      #tfsec:ignore:google-sql-encrypt-in-transit-data
      ssl_mode = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
    }

  }

  root_password = random_password.db_password.result
  depends_on    = [google_service_networking_connection.private_vpc_connection]
}

# --- 7. The Application's Database (Schema) ---
resource "google_sql_database" "database" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_name
}

# --- 8. The Application's User ---
resource "google_sql_user" "user" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_user
  password = random_password.db_password.result
}