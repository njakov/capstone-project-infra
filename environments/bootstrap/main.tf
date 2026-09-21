# ------------------------------------------------------------------------------
# App plane VPC (GKE, Cloud SQL PSA, middleware) — no runner VMs
# ------------------------------------------------------------------------------
module "app_network" {
  source = "../../modules/network"

  project_id    = var.project_id
  region        = var.region
  network_name  = "${var.app_name}-vpc-${var.env}"
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
  # No IAP SSH targets on the app VPC (runners live on the infra VPC)
  iap_ssh_target_tags = []
}

# ------------------------------------------------------------------------------
# Infra plane VPC (GCE infra runners only)
# ------------------------------------------------------------------------------
module "infra_network" {
  source = "../../modules/network"

  project_id          = var.project_id
  region              = var.region
  network_name        = "${var.app_name}-infra-vpc-${var.env}"
  subnet_cidr         = var.infra_subnet_cidr
  pods_cidr           = null
  services_cidr       = null
  iap_ssh_target_tags = ["infra-runner"]
}

# ------------------------------------------------------------------------------
# Bidirectional peering: infra runners → private GKE API (custom routes)
# ------------------------------------------------------------------------------
module "peering" {
  source = "../../modules/network-peering"

  network_a_self_link = module.infra_network.network_self_link
  network_b_self_link = module.app_network.network_self_link
  peering_name_a_to_b = "${var.app_name}-infra-to-app-${var.env}"
  peering_name_b_to_a = "${var.app_name}-app-to-infra-${var.env}"
}

# ------------------------------------------------------------------------------
# Infra-only GitHub Actions runner (register with labels: self-hosted, infra, {env})
# ------------------------------------------------------------------------------
module "runner" {
  source = "../../modules/runner"

  project_id = var.project_id
  env        = var.env
  zone       = "${var.region}-b"

  network_name = module.infra_network.network_name
  subnet_id    = module.infra_network.subnet_id

  depends_on = [module.peering]
}

# Preserve existing app VPC state address after rename module.network → module.app_network
moved {
  from = module.network
  to   = module.app_network
}
