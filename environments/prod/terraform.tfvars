project_id = "project-17c62de2-ec01-476d-908"
region     = "europe-west1"
env        = "prod"
app_name   = "petclinic"

db_tier                    = "db-f1-micro"
gke_min_nodes              = 1
gke_max_nodes              = 2
gke_machine_type           = "e2-standard-2"
gke_node_locations         = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
gke_maintenance_start_time = "03:00"
