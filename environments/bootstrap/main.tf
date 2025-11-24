module "network" {
  source = "../../modules/network"

  project_id    = var.project_id
  region        = var.region
  network_name  = "${var.app_name}-vpc-${var.env}"
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}

module "runner" {
  source = "../../modules/runner"

  project_id = var.project_id
  env        = var.env
  zone       = "${var.region}-b"

  # Connects to the network created above
  network_name = module.network.network_name
  subnet_id    = module.network.subnet_id
}