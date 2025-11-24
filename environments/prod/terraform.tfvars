project_id = "teak-advice-475415-i2"
region     = "europe-west1"
env        = "dev"
app_name   = "petclinic"

db_tier                    = "db-f1-micro"
gke_min_nodes              = 1
gke_max_nodes              = 2
gke_machine_type           = "e2-standard-2"
gke_maintenance_start_time = "03:00"

subnet_cidr           = "10.10.0.0/24"
pods_cidr             = "10.20.0.0/16"
services_cidr         = "10.30.0.0/16"
allowed_source_ranges = ["YOUR.PUBLIC.IP/32"]