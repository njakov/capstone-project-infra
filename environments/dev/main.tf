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

# 1. Get the secret payload (the actual password string)
data "google_secret_manager_secret_version" "db_password" {
  secret  = module.cloud_sql.db_password_secret_version_id # You already output this!
  project = var.project_id
}

# 2. Create a K8s Secret (The App will read this)
resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }
  data = {
    username = module.cloud_sql.db_user
    password = data.google_secret_manager_secret_version.db_password.secret_data
    # Construct the JDBC URL automatically
    url = "jdbc:mysql://${module.cloud_sql.private_ip_address}/${module.cloud_sql.db_name}"
  }
  depends_on = [module.gke]
}

module "runner" {
  source = "../../modules/runner"

  project_id   = var.project_id
  env          = "dev"
  zone         = "${var.region}-b"
  network_name = module.network.network_name
  subnet_id    = module.network.subnet_id
}