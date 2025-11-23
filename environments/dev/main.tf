module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  region       = var.region
  network_name = "${var.app_name}-vpc-${var.env}"
}

module "identity" {
  source = "../../modules/identity"

  project_id    = var.project_id
  env           = var.env
  app_name      = var.app_name
  k8s_namespace = "default"            # Namespace where the app runs in GKE
  k8s_sa_name   = "${var.app_name}-sa" # K8s Service Account name for Workload Identity
}

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id  = var.project_id
  region      = var.region
  environment = var.env

  db_instance_name = "${var.app_name}-db-${var.env}"
  db_name          = var.app_name
  db_user          = var.app_name
  db_tier          = var.db_tier

  network_name = module.network.network_name
  # DB module grants secret access & client roles
  app_service_account_email = module.identity.email

  depends_on = [module.network]
}

module "gke" {
  source = "../../modules/gke"

  project_id   = var.project_id
  region       = var.region
  cluster_name = "${var.app_name}-gke-${var.env}"

  network_name          = module.network.network_name
  subnet_id             = module.network.subnet_id
  subnet_pods_range     = module.network.subnet_pods_range
  subnet_services_range = module.network.subnet_services_range
  subnet_ip_cidr_range  = module.network.subnet_ip_cidr_range

  min_node_count = var.gke_min_nodes
  max_node_count = var.gke_max_nodes
  machine_type   = var.gke_machine_type
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "${var.app_name}-repo-${var.env}"
}

module "middleware" {
  source     = "../../modules/middleware"
  depends_on = [module.gke]
}

module "runner" {
  source = "../../modules/runner"

  project_id   = var.project_id
  env          = var.env
  zone         = "${var.region}-b"
  network_name = module.network.network_name
  subnet_id    = module.network.subnet_id
}
