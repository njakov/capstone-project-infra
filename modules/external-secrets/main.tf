# modules/external-secrets — sync the GitHub App Secret Manager shells into arc-runners.
#
# The operator runs in its own namespace and its ServiceAccount is not granted
# Secret Manager access. Only the arc-runners Kubernetes ServiceAccount, annotated
# with the bootstrap GCP account, is referenced by the SecretStore.
# Helm owns the SecretStore and ExternalSecret so the first plan does not need
# the CRD schema. This module does not create a Kubernetes secret; ExternalSecret
# creationPolicy Owner creates arc-github-app.

locals {
  github_app_id_secret_id              = coalesce(var.github_app_id_secret_id, "arc-github-app-id-${var.env}")
  github_app_installation_id_secret_id = coalesce(var.github_app_installation_id_secret_id, "arc-github-app-installation-id-${var.env}")
  github_app_private_key_secret_id     = coalesce(var.github_app_private_key_secret_id, "arc-github-app-private-key-${var.env}")

  secret_store_name    = "gcpsm"
  external_secret_name = "arc-github-app"
  target_secret_name   = "arc-github-app"
  controller_sa_name   = "external-secrets"
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_version
  namespace        = var.controller_namespace
  create_namespace = true
  timeout          = 600
  wait             = true

  values = [
    yamlencode({
      installCRDs = true
      # Token create lets the controller mint a token for the arc-runners
      # ServiceAccount named in the SecretStore. Default is true; keep it explicit.
      rbac = {
        serviceAccountTokenCreate = true
      }
      # No GCP annotation: this identity cannot read Secret Manager.
      serviceAccount = {
        create      = true
        name        = local.controller_sa_name
        annotations = {}
      }
    })
  ]
}

resource "kubernetes_service_account_v1" "external_secrets" {
  metadata {
    name      = var.k8s_service_account_name
    namespace = var.arc_runners_namespace
    annotations = {
      "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
    }
    labels = {
      "app.kubernetes.io/name"      = "external-secrets"
      "app.kubernetes.io/component" = "github-app-sync"
    }
  }
}

resource "helm_release" "github_app" {
  name      = "arc-github-app"
  chart     = "${path.module}/charts/github-app"
  namespace = var.arc_runners_namespace
  timeout   = 600
  wait      = true

  # CRDs come from the operator release in the same apply. Skip OpenAPI
  # validation so this plan does not require the schema to be installed yet.
  disable_openapi_validation = true

  values = [
    yamlencode({
      projectID                       = var.project_id
      serviceAccountName              = var.k8s_service_account_name
      secretStoreName                 = local.secret_store_name
      externalSecretName              = local.external_secret_name
      targetSecretName                = local.target_secret_name
      githubAppIdSecretId             = local.github_app_id_secret_id
      githubAppInstallationIdSecretId = local.github_app_installation_id_secret_id
      githubAppPrivateKeySecretId     = local.github_app_private_key_secret_id
    })
  ]

  depends_on = [
    helm_release.external_secrets,
    kubernetes_service_account_v1.external_secrets,
  ]
}
