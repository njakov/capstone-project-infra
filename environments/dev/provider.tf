terraform {
  required_version = "1.16.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.12.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
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

# DNS endpoint presents a Google-managed certificate. Passing the cluster CA fails TLS.
provider "helm" {
  kubernetes = {
    host  = "https://${module.gke.cluster_dns_endpoint}"
    token = data.google_client_config.default.access_token
  }
}

provider "kubernetes" {
  host  = "https://${module.gke.cluster_dns_endpoint}"
  token = data.google_client_config.default.access_token
}