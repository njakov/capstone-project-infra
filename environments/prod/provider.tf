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

# DNS endpoint presents a Google-managed certificate. Passing the cluster CA fails TLS.
# The auth plugin refreshes the Google token across a long apply.
provider "helm" {
  kubernetes = {
    host = "https://${module.gke.cluster_dns_endpoint}"
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}

provider "kubernetes" {
  host = "https://${module.gke.cluster_dns_endpoint}"
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}