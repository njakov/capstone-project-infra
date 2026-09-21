# Prod project ID (display name: PetClinic Prod). Never reuse the dev UUID.
project_id = "petclinic-gke-prod"
region     = "europe-west1"
env        = "prod"
app_name   = "petclinic"

db_tier              = "db-g1-small"
db_availability_type = "REGIONAL"

gke_cluster_location       = "europe-west1"
gke_node_locations         = ["europe-west1-c", "europe-west1-d"]
gke_min_nodes              = 1
gke_max_nodes              = 2
gke_machine_type           = "e2-standard-2"
gke_maintenance_start_time = "03:00"
master_ipv4_cidr_block     = "172.16.0.16/28"

# App plane CIDRs (env-owned app VPC; distinct from dev)
subnet_cidr   = "10.11.0.0/24"
pods_cidr     = "10.21.0.0/16"
services_cidr = "10.31.0.0/16"

# allowed_source_ranges: set TF_VAR_allowed_source_ranges (GitHub Environment
# ALLOWED_SOURCE_RANGES, or local export). Do not commit a home IP here.

# ARC: create SM shells on apply; flip arc_install_charts after adding GitHub App versions
# Prod cutover only after Gate E is green on dev (see docs/arc-cutover.md).
enable_arc         = true
arc_install_charts = false
