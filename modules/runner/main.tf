# Service Account for the Runner
resource "google_service_account" "runner_sa" {
  project      = var.project_id
  account_id   = "github-runner-sa-${var.env}"
  display_name = "GitHub Runner Service Account for ${var.env} environment"
}

locals {
  required_roles = [
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",             # To manage VPC/NAT/Firewalls
    "roles/container.admin",                   # To manage GKE
    "roles/cloudsql.admin",                    # To manage Cloud SQL
    "roles/secretmanager.admin",               # To manage Secrets
    "roles/iam.serviceAccountUser",            # To attach SAs to GKE nodes/VMs
    "roles/iam.roleAdmin",                     # To create custom roles (if needed)
    "roles/resourcemanager.projectIamAdmin",   # To grant IAM bindings
    "roles/storage.objectAdmin",               # To read/write Terraform State
    "roles/serviceusage.serviceUsageConsumer", # To enable APIs
    "roles/artifactregistry.writer",           # To push images to Artifact Registry
    "roles/iam.serviceAccountAdmin"
  ]
}

# tfsec:ignore:google-iam-no-project-level-service-account-impersonation
resource "google_project_iam_member" "runner_permissions" {
  for_each = toset(local.required_roles)
  project  = var.project_id
  # tfsec:ignore:google-iam-no-project-level-service-account-impersonation
  # Terraform Runner needs to attach Service Accounts to the resources it creates.
  role   = each.value
  member = "serviceAccount:${google_service_account.runner_sa.email}"
}

# tfsec:ignore:google-compute-no-project-wide-ssh-keys
resource "google_compute_instance" "runner" {
  project      = var.project_id
  name         = "runner-vm-${var.env}"
  machine_type = "e2-standard-2"
  zone         = var.zone

  metadata = {
    block-project-ssh-keys = "true"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # tfsec:ignore:google-compute-vm-disk-encryption-customer-key
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_id
  }

  service_account {
    email  = google_service_account.runner_sa.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = file("${path.module}/startup.sh")

  tags = ["private-runner"]
}