project_id = "project-62ebde90-46b7-4e70-b59"
region     = "europe-west1"
env        = "dev"
app_name   = "petclinic"

# App plane (distinct from prod within the same GCP project)
subnet_cidr   = "10.10.0.0/24"
pods_cidr     = "10.20.0.0/16"
services_cidr = "10.30.0.0/16"

# Infra plane (GCE runners)
infra_subnet_cidr = "10.50.0.0/24"
