# ------------------------------------------------------------------------------
# Infra plane VPC (GCE infra runners only)
# App VPC + peering are created by the env apply (see Phase 2).
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
# Infra-only GitHub Actions runner (register with labels: self-hosted, infra, {env})
# ------------------------------------------------------------------------------
module "runner" {
  source = "../../modules/runner"

  project_id   = var.project_id
  env          = var.env
  zone         = "${var.region}-b"
  machine_type = "e2-medium"

  network_name = module.infra_network.network_name
  subnet_id    = module.infra_network.subnet_id
}

# ------------------------------------------------------------------------------
# Workload SAs + project IAM + D6 resource-level grants for the runner.
# After a successful apply, lock terraform-sa: ./scripts/lock-terraform-sa.sh <env>
# ------------------------------------------------------------------------------
module "bootstrap_iam" {
  source = "../../modules/bootstrap-iam"

  project_id      = var.project_id
  env             = var.env
  app_name        = var.app_name
  runner_sa_email = module.runner.service_account_email
}
