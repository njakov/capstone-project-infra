project_id = "project-62ebde90-46b7-4e70-b59"
region     = "europe-west1"
env        = "prod"
app_name   = "petclinic"

# App plane (distinct from dev within the same GCP project)
subnet_cidr   = "10.11.0.0/24"
pods_cidr     = "10.21.0.0/16"
services_cidr = "10.31.0.0/16"

# Infra plane (GCE runners)
infra_subnet_cidr = "10.51.0.0/24"
