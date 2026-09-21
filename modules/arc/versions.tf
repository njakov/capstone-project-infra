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
