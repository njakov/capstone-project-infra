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