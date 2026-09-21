project_id = "project-62ebde90-46b7-4e70-b59"
region     = "europe-west1"
env        = "prod"
app_name   = "petclinic"

db_tier                    = "db-f1-micro"
gke_min_nodes              = 1
gke_max_nodes              = 2
gke_machine_type           = "e2-standard-2"
gke_node_locations         = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
gke_maintenance_start_time = "03:00"
master_ipv4_cidr_block     = "172.16.0.16/28"

allowed_source_ranges = ["YOUR.PUBLIC.IP/32"]

# ARC: create SM shells on apply; flip arc_install_charts after adding GitHub App versions
# Prod cutover only after Gate E is green on dev (see docs/arc-cutover.md).
enable_arc         = true
arc_install_charts = false

