terraform {
  required_version = "1.14.1"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.12.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    # Recommended to keep for flexibility
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

# REQUIRED for Requirement #2 ("Use Helm")
provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  }
}

# OPTIONAL but Recommended (Keep it)
provider "kubernetes" {
  host                   = "https://${module.gke.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
}