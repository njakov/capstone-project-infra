# --- 1. Dedicated Service Account (Least Privilege) ---
resource "google_service_account" "runner_sa" {
  project      = var.project_id
  account_id   = "github-runner-sa"
  display_name = "GitHub Runner Service Account"
}

# List of specific roles needed to provision the Capstone Infrastructure
# This replaces the insecure "roles/editor"
locals {
  required_roles = [
    "roles/compute.networkAdmin",             # To manage VPC/NAT/Firewalls
    "roles/container.admin",                  # To manage GKE
    "roles/cloudsql.admin",                   # To manage Cloud SQL
    "roles/secretmanager.admin",              # To manage Secrets
    "roles/iam.serviceAccountUser",           # To attach SAs to GKE nodes/VMs
    "roles/iam.roleAdmin",                    # To create custom roles (if needed)
    "roles/resourcemanager.projectIamAdmin",  # To grant IAM bindings
    "roles/storage.objectAdmin",              # To read/write Terraform State
    "roles/serviceusage.serviceUsageConsumer" # To enable APIs
  ]
}

resource "google_project_iam_member" "runner_permissions" {
  for_each = toset(local.required_roles)
  project  = var.project_id
  # tfsec:ignore:google-iam-no-project-level-service-account-impersonation
  # Reason: Terraform Runner needs to attach Service Accounts to the resources it creates.
  role   = each.value
  member = "serviceAccount:${google_service_account.runner_sa.email}"
}

# --- 2. Hardened Runner VM ---
# tfsec:ignore:google-compute-no-project-wide-ssh-keys
resource "google_compute_instance" "runner" {
  project      = var.project_id
  name         = "${var.env}-runner-vm"
  machine_type = "e2-standard-2"
  zone         = var.zone

  metadata = {
    block-project-ssh-keys = "true"
  }

  # Best Practice: Enable Shielded VM features
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
    # No access_config block = Private IP only (Enhanced Security)
  }

  service_account {
    email  = google_service_account.runner_sa.email
    scopes = ["cloud-platform"]
  }

  # Best Practice: 'set -e' stops execution on error
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    # Prevent running if already installed
    if [ -x "$(command -v terraform)" ]; then
      echo "Tools already installed. Skipping."
      exit 0
    fi

    echo "Installing dependencies..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release unzip software-properties-common git jq

    # Install Docker
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    usermod -aG docker ubuntu

    # Install Terraform (Pinned version recommended for production, using latest for capstone)
    curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
    apt-get update && apt-get install -y terraform

    # Install Security Scanners (TFLint & TFSec)
    curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
    curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

    echo "Installation complete. Ready for runner registration."
  EOT

  tags = ["private-runner"]
}