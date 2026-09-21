# ------------------------------------------------------------------------------
# 0. PRE-CREATED WORKLOAD SAs (bootstrap-iam; deterministic account_ids)
# ------------------------------------------------------------------------------
locals {
  node_sa_email             = "${var.app_name}-gke-${var.env}-node-sa@${var.project_id}.iam.gserviceaccount.com"
  app_sa_email              = "${var.app_name}-sa-${var.env}@${var.project_id}.iam.gserviceaccount.com"
  app_runner_sa_email       = "github-app-runner-sa-${var.env}@${var.project_id}.iam.gserviceaccount.com"
  external_secrets_sa_email = "external-secrets-${var.env}@${var.project_id}.iam.gserviceaccount.com"
}

# ------------------------------------------------------------------------------
# 1. APP NETWORK: VPC + NAT (env-owned; CIDRs from tfvars)
# ------------------------------------------------------------------------------
module "app_network" {
  source = "../../modules/network"

  project_id    = var.project_id
  region        = var.region
  network_name  = "${var.app_name}-vpc-${var.env}"
  subnet_cidr   = var.subnet_cidr
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
  # No IAP SSH on the app VPC (infra runners live on the infra VPC)
  iap_ssh_target_tags = []
}

# ------------------------------------------------------------------------------
# 2. INFRA DISCOVERY: bootstrap-created infra VPC (deterministic names)
# ------------------------------------------------------------------------------
data "google_compute_network" "infra_vpc" {
  name    = "${var.app_name}-infra-vpc-${var.env}"
  project = var.project_id
}

data "google_compute_subnetwork" "infra_subnet" {
  name    = "${var.app_name}-infra-vpc-${var.env}-private"
  region  = var.region
  project = var.project_id
}

# ------------------------------------------------------------------------------
# 3. PEERING: both legs connect the infra and app VPCs.
# Control-plane access for Terraform is the GKE DNS endpoint, not these routes.
# ------------------------------------------------------------------------------
module "peering" {
  source = "../../modules/network-peering"

  network_a_self_link = data.google_compute_network.infra_vpc.self_link
  network_b_self_link = module.app_network.network_self_link
  peering_name_a_to_b = "${var.app_name}-infra-to-app-${var.env}"
  peering_name_b_to_a = "${var.app_name}-app-to-infra-${var.env}"
}

# ------------------------------------------------------------------------------
# 4. IDENTITY: Workload Identity plus app-runner Kubernetes RBAC.
# ingress-nginx must exist first (middleware Helm creates that namespace).
# ------------------------------------------------------------------------------
module "identity" {
  source     = "../../modules/identity"
  depends_on = [module.gke, module.middleware]

  project_id                = var.project_id
  app_sa_email              = local.app_sa_email
  k8s_namespace             = "petclinic"
  k8s_sa_name               = var.app_name
  app_runner_sa_email       = local.app_runner_sa_email
  arc_runners_namespace     = "arc-runners"
  arc_runner_k8s_sa_name    = "arc-runner"
  external_secrets_sa_email = local.external_secrets_sa_email
}

# ------------------------------------------------------------------------------
# 5. DATABASE: Cloud SQL (secret accessor IAM only; cloudsql.client in bootstrap)
# ------------------------------------------------------------------------------
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id  = var.project_id
  region      = var.region
  environment = var.env

  app_name          = var.app_name
  db_instance_name  = "${var.app_name}-db-${var.env}"
  db_name           = var.app_name
  db_user           = var.app_name
  db_tier           = var.db_tier
  availability_type = var.db_availability_type

  network_name              = module.app_network.network_name
  app_service_account_email = local.app_sa_email
  deletion_protection       = var.deletion_protection
}

# ------------------------------------------------------------------------------
# 6. KUBERNETES: GKE Cluster (DNS endpoint; private nodes and private IP endpoint stay on)
# ------------------------------------------------------------------------------
module "gke" {
  source     = "../../modules/gke"
  depends_on = [module.peering]

  project_id                 = var.project_id
  cluster_location           = var.gke_cluster_location
  cluster_name               = "${var.app_name}-gke-${var.env}"
  node_service_account_email = local.node_sa_email

  network_name = module.app_network.network_name
  subnet_id    = module.app_network.subnet_id

  subnet_pods_range     = "pods"
  subnet_services_range = "services"

  subnet_ip_cidr_range = module.app_network.subnet_ip_cidr_range

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
  deletion_protection    = var.deletion_protection

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
# 7. ARTIFACTS: Docker Registry
# ------------------------------------------------------------------------------
module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "${var.app_name}-repo-${var.env}"
  writer_member = "serviceAccount:${local.app_runner_sa_email}"
  reader_member = "serviceAccount:${local.node_sa_email}"
}

# ------------------------------------------------------------------------------
# 8. MIDDLEWARE: Helm Charts
# ------------------------------------------------------------------------------
module "middleware" {
  source     = "../../modules/middleware"
  depends_on = [module.gke]

  allowed_source_ranges  = var.allowed_source_ranges
  grafana_admin_password = var.grafana_admin_password
}

# ------------------------------------------------------------------------------
# 9. ARC: ephemeral app runners (same cluster; least-privilege WI SA)
#     Shells and the arc-runners namespace. Leave arc_install_charts false
#     until ExternalSecret arc-github-app is Ready.
# ------------------------------------------------------------------------------
module "arc" {
  count = var.enable_arc ? 1 : 0

  source     = "../../modules/arc"
  depends_on = [module.gke, module.identity]

  project_id                    = var.project_id
  env                           = var.env
  app_name                      = var.app_name
  github_config_url             = var.arc_github_config_url
  app_runner_gcp_sa_email       = module.identity.app_runner_email
  external_secrets_gcp_sa_email = local.external_secrets_sa_email
  install_charts                = var.arc_install_charts
  min_runners                   = var.arc_min_runners
  max_runners                   = var.arc_max_runners
  https_egress_except_cidrs = [
    var.subnet_cidr,
    var.pods_cidr,
    var.services_cidr,
    data.google_compute_subnetwork.infra_subnet.ip_cidr_range,
  ]
}

# ------------------------------------------------------------------------------
# 10. EXTERNAL SECRETS: operator plus the arc-runners identity that syncs
#     the GitHub App shells into secret arc-github-app.
# ------------------------------------------------------------------------------
module "external_secrets" {
  count = var.enable_arc ? 1 : 0

  source     = "../../modules/external-secrets"
  depends_on = [module.gke, module.arc, module.identity]

  project_id                = var.project_id
  env                       = var.env
  gcp_service_account_email = local.external_secrets_sa_email
  arc_runners_namespace     = "arc-runners"
}
