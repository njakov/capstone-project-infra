module "network" {
  source = "../../modules/network"

  project_id   = var.project_id # <-- Use var.
  region       = var.region     # <-- Use var.
  network_name = "petclinic-vpc-dev"
}

module "gke" {
  source = "../../modules/gke"

  # Pass in project/region variables
  project_id   = var.project_id
  region       = var.region
  cluster_name = "petclinic-gke-dev" # 'dev' specific name

  network_name          = module.network.network_name
  subnet_id             = module.network.subnet_id
  subnet_pods_range     = module.network.subnet_pods_range
  subnet_services_range = module.network.subnet_services_range
  subnet_ip_cidr_range  = module.network.subnet_ip_cidr_range

  # Set autoscaling for the dev environment
  min_node_count = 1
  max_node_count = 2
}


module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id       = var.project_id
  region           = var.region
  db_instance_name = "petclinic-db-dev"
  db_name          = "petclinic"
  db_user          = "petclinic"

  # --- STITCHING: Connect the DB to the Network module's output ---
  network_name = module.network.network_name

  # This module needs to run after the network is created
  depends_on = [module.network]
}

resource "google_service_account" "petclinic_sa" {
  project      = var.project_id
  account_id   = "petclinic-app-sa"
  display_name = "Petclinic Application Service Account"
}

# 2. Grant Cloud SQL Client role to the GSA
resource "google_project_iam_member" "petclinic_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.petclinic_sa.email}"
}

# 3. Bind the GSA to the Kubernetes Service Account (Workload Identity)
# Note: We assume the K8s namespace is "default" and KSA name is "petclinic-sa"
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.petclinic_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/petclinic-sa]"
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "petclinic-repo-dev"
}

module "runner" {
  source = "../../modules/runner"

  project_id   = var.project_id
  env          = "dev"
  zone         = "${var.region}-b"
  network_name = module.network.network_name
  subnet_id    = module.network.subnet_id
}

# Create Secrets in Google Secret Manager
resource "google_secret_manager_secret" "db_username" {
  project   = var.project_id
  secret_id = "petclinic-db-username"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_username_val" {
  secret      = google_secret_manager_secret.db_username.id
  secret_data = module.cloud_sql.db_user
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "petclinic-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password_val" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = module.cloud_sql.db_password_plain
}

resource "google_secret_manager_secret" "db_url" {
  project   = var.project_id
  secret_id = "petclinic-db-url"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_url_val" {
  secret = google_secret_manager_secret.db_url.id
  # Construct the URL just like you did before
  secret_data = "jdbc:mysql://127.0.0.1:3306/${module.cloud_sql.db_name}"
}

# Grant the Google Service Account access to Secret Manager
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.petclinic_sa.email}"
}