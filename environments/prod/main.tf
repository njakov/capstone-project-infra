# ------------------------------------------------------------------------------
# 1. DISCOVERY: Find the Network & Subnet created by the Bootstrap Layer
# ------------------------------------------------------------------------------
data "google_compute_network" "vpc" {
  name    = "${var.app_name}-vpc-${var.env}"
  project = var.project_id
}

data "google_compute_subnetwork" "private_subnet" {
  name    = "${var.app_name}-vpc-${var.env}-private"
  region  = var.region
  project = var.project_id
}

# ------------------------------------------------------------------------------
# 2. IDENTITY: Create the Application Service Account
# ------------------------------------------------------------------------------
module "identity" {
  source = "../../modules/identity"

  project_id    = var.project_id
  env           = var.env
  app_name      = var.app_name
  k8s_namespace = "default"
  k8s_sa_name   = "${var.app_name}-sa"
}

# ------------------------------------------------------------------------------
# 3. DATABASE: Cloud SQL
# ------------------------------------------------------------------------------
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id  = var.project_id
  region      = var.region
  environment = var.env

  app_name         = var.app_name
  db_instance_name = "${var.app_name}-db-${var.env}"
  db_name          = var.app_name
  db_user          = var.app_name
  db_tier          = var.db_tier

  network_name              = data.google_compute_network.vpc.name
  app_service_account_email = module.identity.email
}

# ------------------------------------------------------------------------------
# 4. KUBERNETES: GKE Cluster
# ------------------------------------------------------------------------------
module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "${var.app_name}-gke-${var.env}"

  network_name = data.google_compute_network.vpc.name
  subnet_id    = data.google_compute_subnetwork.private_subnet.id

  subnet_pods_range     = "pods"
  subnet_services_range = "services"

  subnet_ip_cidr_range = data.google_compute_subnetwork.private_subnet.ip_cidr_range

  min_node_count         = var.gke_min_nodes
  max_node_count         = var.gke_max_nodes
  machine_type           = var.gke_machine_type
  maintenance_start_time = var.gke_maintenance_start_time
}

# ------------------------------------------------------------------------------
# 5. ARTIFACTS: Docker Registry
# ------------------------------------------------------------------------------
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "${var.app_name}-repo-${var.env}"
}

# ------------------------------------------------------------------------------
# 6. MIDDLEWARE: Helm Charts
# ------------------------------------------------------------------------------
module "middleware" {
  source     = "../../modules/middleware"
  depends_on = [module.gke]
}