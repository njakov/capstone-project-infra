project_id = "project-62ebde90-46b7-4e70-b59"
region     = "europe-west1"
env        = "dev"
app_name   = "petclinic"

db_tier              = "db-f1-micro"
db_availability_type = "ZONAL"

gke_cluster_location       = "europe-west1-c"
gke_node_locations         = ["europe-west1-c"]
gke_min_nodes              = 1
gke_max_nodes              = 2
gke_machine_type           = "e2-standard-2"
gke_maintenance_start_time = "03:00"
master_ipv4_cidr_block     = "172.16.0.0/28"

# App plane CIDRs (env-owned app VPC)
subnet_cidr   = "10.10.0.0/24"
pods_cidr     = "10.20.0.0/16"
services_cidr = "10.30.0.0/16"

# allowed_source_ranges: set TF_VAR_allowed_source_ranges (GitHub Environment
# ALLOWED_SOURCE_RANGES, or local export). Do not commit a home IP here.

# ARC: create SM shells on apply; flip arc_install_charts after adding GitHub App versions
enable_arc         = true
arc_install_charts = false
