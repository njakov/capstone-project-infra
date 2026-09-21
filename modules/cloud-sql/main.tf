# modules/cloud-sql/main.tf
# APIs (servicenetworking, secretmanager) are enabled by scripts/setup_gcp.sh as Owner.
# Do not use google_project_service here — serviceUsageConsumer cannot enable APIs.

# Create a Private IP Range for the Peering
resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "sql-private-range-${var.db_instance_name}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  ip_version    = "IPV4"
  prefix_length = 24
  network       = "projects/${var.project_id}/global/networks/${var.network_name}"
}

# Create the VPC Peering Connection
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = "projects/${var.project_id}/global/networks/${var.network_name}"
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# Preserve the existing application password when renaming the resource.
moved {
  from = random_password.db_password
  to   = random_password.app_password
}

# Generate independent credentials for the application and root accounts.
resource "random_password" "app_password" {
  length  = 16
  special = false
  keepers = {
    rotation_trigger = "rotate-2025-11-18"
  }
}

resource "random_password" "root_password" {
  length  = 32
  special = true
  keepers = {
    rotation_trigger = "rotate-2026-08-27"
  }
}

# The Cloud SQL Instance
resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = var.db_instance_name
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.db_tier
    availability_type = var.availability_type
    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/${var.network_name}"
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "20:55"
    }

  }

  root_password = random_password.root_password.result
  depends_on    = [google_service_networking_connection.private_vpc_connection]
}

# The Application's Database
resource "google_sql_database" "database" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_name
}

# The Application's User
resource "google_sql_user" "user" {
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = var.db_user
  password = random_password.app_password.result
  host     = "%"
}

# Create Secrets in Google Secret Manager
resource "google_secret_manager_secret" "db_username" {
  project   = var.project_id
  secret_id = "${var.app_name}-db-username-${var.environment}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_username_val" {
  secret      = google_secret_manager_secret.db_username.id
  secret_data = google_sql_user.user.name
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.app_name}-db-password-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password_val" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.app_password.result
}

# Store the root credential separately. No accessor binding is granted to the
# application service account; administrative access must be granted explicitly.
resource "google_secret_manager_secret" "db_root_password" {
  project   = var.project_id
  secret_id = "${var.app_name}-db-root-password-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_root_password_val" {
  secret      = google_secret_manager_secret.db_root_password.id
  secret_data = random_password.root_password.result
}

resource "google_secret_manager_secret" "db_url" {
  project   = var.project_id
  secret_id = "${var.app_name}-db-url-${var.environment}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_url_val" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = "jdbc:mysql://127.0.0.1:3306/${google_sql_database.database.name}"
}

resource "google_secret_manager_secret_iam_member" "username_access" {
  secret_id = google_secret_manager_secret.db_username.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "password_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_account_email}"
}

resource "google_secret_manager_secret_iam_member" "url_access" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.app_service_account_email}"
}

# cloudsql.client (conditioned) is granted in bootstrap-iam; do not re-bind here.
