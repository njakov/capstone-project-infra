# Day-2 infra runner SA: workload *admin roles + networkAdmin; no project IAM/SA admin.
# Resource-level SA grants for node/app/app-runner live in modules/bootstrap-iam (D6).
resource "google_service_account" "runner_sa" {
  project      = var.project_id
  account_id   = "github-infra-runner-sa-${var.env}"
  display_name = "GitHub Infra Runner Service Account for ${var.env}"
}

locals {
  # Keep networkAdmin (app VPC, peering, SQL PSA). Drop projectIamAdmin and
  # project-level serviceAccountAdmin/User — those were day-1 chicken-egg only.
  required_roles = [
    "roles/compute.networkAdmin",
    "roles/container.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/serviceusage.serviceUsageConsumer",
  ]
}

resource "google_project_iam_member" "runner_permissions" {
  for_each = toset(local.required_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.runner_sa.email}"
}

resource "google_storage_bucket_iam_member" "runner_state_access" {
  bucket = "terraform-state-bucket-${var.project_id}"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runner_sa.email}"
}

# Google no longer grants iam.serviceAccounts.actAs to the SA creator, so
# attaching this SA to the VM 403s without an explicit binding. Resource-level
# serviceAccountUser on the runner SA only — never project-level on terraform-sa.
resource "google_service_account_iam_member" "terraform_sa_act_as_runner" {
  service_account_id = google_service_account.runner_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:terraform-sa@${var.project_id}.iam.gserviceaccount.com"
}

# tfsec:ignore:google-compute-no-project-wide-ssh-keys
resource "google_compute_instance" "runner" {
  project      = var.project_id
  name         = "runner-vm-infra-${var.env}"
  machine_type = var.machine_type
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

  # Register in GitHub with labels: self-hosted, infra, {env}
  tags = ["infra-runner"]

  depends_on = [google_service_account_iam_member.terraform_sa_act_as_runner]
}
