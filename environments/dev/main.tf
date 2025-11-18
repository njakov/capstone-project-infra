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

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "petclinic-repo-dev"
}

# 1. Get the latest version of the secret by NAME
data "google_secret_manager_secret_version" "db_password" {
  secret  = module.cloud_sql.secret_id # <--- Passing the name here
  project = var.project_id
}


# --- 1. Dedicated Namespace ---
resource "kubernetes_namespace" "petclinic" {
  metadata {
    name = "petclinic-app" # Deploying to a separate namespace is best practice
  }
}

# --- 2. Application Google Service Account (GSA) ---
resource "google_service_account" "petclinic_gsa" {
  account_id   = "petclinic-gsa"
  display_name = "PetClinic GSA for Workload Identity"
}

# --- 3. Kubernetes Service Account (KSA) with Workload Identity Annotation ---
resource "kubernetes_service_account" "petclinic_ksa" {
  metadata {
    name      = "petclinic-ksa"
    namespace = kubernetes_namespace.petclinic.metadata[0].name
    annotations = {
      # This links the KSA to the GSA
      "iam.gke.io/sa" = "petclinic-gsa@${var.project_id}.iam.gserviceaccount.com"
    }
  }
}

# --- 4. Workload Identity Binding (KSA can act as GSA) ---
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.petclinic_gsa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${kubernetes_namespace.petclinic.metadata[0].name}/${kubernetes_service_account.petclinic_ksa.metadata[0].name}]"
}

# --- 5. Secret Reader Access (GSA can read the secret) ---
resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  secret_id = module.cloud_sql.secret_id # The Secret Manager resource name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.petclinic_gsa.email}"
}


module "runner" {
  source = "../../modules/runner"

  project_id   = var.project_id
  env          = "dev"
  zone         = "${var.region}-b"
  network_name = module.network.network_name
  subnet_id    = module.network.subnet_id
}