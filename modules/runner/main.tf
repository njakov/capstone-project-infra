# --- 1. Dedicated Service Account (Least Privilege) ---
resource "google_service_account" "runner_sa" {
  project      = var.project_id
  account_id   = "github-runner-sa"
  display_name = "GitHub Runner Service Account"
}

locals {
  required_roles = [
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkAdmin",              # To manage VPC/NAT/Firewalls
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

  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "Starting Runner Setup on $(hostname)..."

    # 1. Install Base Dependencies
    echo "Installing Base Dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release unzip software-properties-common git jq wget apt-transport-https

    # 2. Install Docker (Modern Keyring Method)
    if ! command -v docker &> /dev/null; then
      echo "Installing Docker..."
      mkdir -p /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # CRITICAL FIX: Allow ANY user to use Docker
    chmod 666 /var/run/docker.sock

    # 3. Install Terraform
    if ! command -v terraform &> /dev/null; then
      echo "Installing Terraform..."
      wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
      apt-get update
      apt-get install -y terraform
    fi

    # 4. NEW: Add Google Cloud SDK Repo & Install Kubectl
    if ! command -v kubectl &> /dev/null; then
      echo "Adding Google Cloud SDK Repo..."
      # Add the GPG key
      curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
      
      # Add the repository source
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list

      # Update and Install
      apt-get update
      echo "Installing Kubectl and Auth Plugin..."
      apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl
    fi

    # 5. Install Helm
    if ! command -v helm &> /dev/null; then
      echo "Installing Helm..."
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # 6. Install Security Scanners
    echo "Installing Scanners..."
    curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
    curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

    # 7. Configure Docker Auth
    echo "Configuring Docker Auth..."
    gcloud auth configure-docker --quiet

    echo "✅ Installation Complete! Runner is ready."
  EOT

  tags = ["private-runner"]
}