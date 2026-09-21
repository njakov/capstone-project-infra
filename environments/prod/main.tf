# ------------------------------------------------------------------------------
# 1. DISCOVERY: App VPC (bootstrap) + infra subnet for private GKE API access
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

data "google_compute_subnetwork" "infra_subnet" {
  name    = "${var.app_name}-infra-vpc-${var.env}-private"
  region  = var.region
  project = var.project_id
}

# ------------------------------------------------------------------------------
# 2. IDENTITY: Application SA + least-privilege ARC app-runner SA
# ------------------------------------------------------------------------------
module "identity" {
  source     = "../../modules/identity"
  depends_on = [module.gke]

  project_id    = var.project_id
  env           = var.env
  app_name      = var.app_name
  k8s_namespace = "petclinic"
  k8s_sa_name   = var.app_name

  # ARC K8s SA binding (namespace/SA created when ARC module is installed)
  create_app_runner_sa   = true
  arc_runners_namespace  = "arc-runners"
  arc_runner_k8s_sa_name = "arc-runner"
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

  additional_master_authorized_networks = [
    {
      display_name = "infra-runner-subnet"
      cidr_block   = data.google_compute_subnetwork.infra_subnet.ip_cidr_range
    }
  ]

  min_node_count         = var.gke_min_nodes
  max_node_count         = var.gke_max_nodes
  machine_type           = var.gke_machine_type
  node_locations         = var.gke_node_locations
  maintenance_start_time = var.gke_maintenance_start_time
  master_ipv4_cidr_block = var.master_ipv4_cidr_block

  # Dedicated tainted pool for ARC ephemeral runners (Kaniko-friendly COS)
  enable_runner_node_pool = true
  runner_machine_type     = var.gke_runner_machine_type
  runner_min_node_count   = var.gke_runner_min_nodes
  runner_max_node_count   = var.gke_runner_max_nodes

  labels = {
    environment = var.env
    project     = var.project_id
    app         = var.app_name
  }

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

  allowed_source_ranges  = var.allowed_source_ranges
  grafana_admin_password = var.grafana_admin_password
}

# ------------------------------------------------------------------------------
# 7. ARC: ephemeral app runners (same cluster; least-privilege WI SA)
#     Set arc_install_charts = false until GitHub App secret versions exist.
# ------------------------------------------------------------------------------
module "arc" {
  count = var.enable_arc ? 1 : 0

  source     = "../../modules/arc"
  depends_on = [module.gke, module.identity]

  project_id              = var.project_id
  env                     = var.env
  app_name                = var.app_name
  github_config_url       = var.arc_github_config_url
  app_runner_gcp_sa_email = module.identity.app_runner_email
  install_charts          = var.arc_install_charts
  min_runners             = var.arc_min_runners
  max_runners             = var.arc_max_runners
}
