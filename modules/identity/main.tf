# Workload Identity bindings and app-runner Kubernetes RBAC.
# SAs and project IAM live in bootstrap-iam.
# Do not add project-level IAM member resources here — day-2 runner is not project IAM admin.
# The caller must create the ingress-nginx namespace before this module (middleware Helm).

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = local.app_sa_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_sa_name}]"
}

resource "google_service_account_iam_member" "app_runner_workload_identity" {
  count = var.app_runner_sa_email != "" ? 1 : 0

  service_account_id = local.app_runner_sa_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.arc_runners_namespace}/${var.arc_runner_k8s_sa_name}]"
}

# KSA external-secrets in arc-runners assumes the GCP account that reads the GitHub App PEM.
resource "google_service_account_iam_member" "external_secrets_workload_identity" {
  count = var.external_secrets_sa_email != "" ? 1 : 0

  service_account_id = local.external_secrets_sa_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.arc_runners_namespace}/${var.external_secrets_k8s_sa_name}]"
}

locals {
  app_runner_rbac_count = var.app_runner_sa_email != "" ? 1 : 0

  # hashicorp/google 7.12 accepts only projects/{project}/serviceAccounts/{email}.
  # Empty optional emails are not planned (count = 0); the placeholder keeps the
  # string valid if the provider still evaluates the argument.
  app_sa_id              = "projects/${var.project_id}/serviceAccounts/${var.app_sa_email}"
  app_runner_sa_id       = "projects/${var.project_id}/serviceAccounts/${coalesce(var.app_runner_sa_email, "placeholder@${var.project_id}.iam.gserviceaccount.com")}"
  external_secrets_sa_id = "projects/${var.project_id}/serviceAccounts/${coalesce(var.external_secrets_sa_email, "placeholder@${var.project_id}.iam.gserviceaccount.com")}"
}

resource "kubernetes_namespace_v1" "petclinic" {
  metadata {
    name = var.k8s_namespace
    labels = {
      "app.kubernetes.io/name"                     = var.k8s_namespace
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/warn"            = "restricted"
    }
  }
}

# Helm deploy rights for github-app-runner-sa. Secrets here do not include
# arc-github-app, which lives in arc-runners and has no binding for this user.
resource "kubernetes_role_v1" "app_runner_deploy" {
  count = local.app_runner_rbac_count

  metadata {
    name      = "app-runner-deploy"
    namespace = kubernetes_namespace_v1.petclinic.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "deployments/scale"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "serviceaccounts", "secrets", "pods"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["secrets-store.csi.x-k8s.io"]
    resources  = ["secretproviderclasses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors", "prometheusrules"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "app_runner_deploy" {
  count = local.app_runner_rbac_count

  metadata {
    name      = "app-runner-deploy"
    namespace = kubernetes_namespace_v1.petclinic.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app_runner_deploy[0].metadata[0].name
  }

  subject {
    kind      = "User"
    name      = var.app_runner_sa_email
    api_group = "rbac.authorization.k8s.io"
  }
}

# manual-deploy reads the ingress-nginx LoadBalancer address. No Secret access.
resource "kubernetes_role_v1" "app_runner_ingress_read" {
  count = local.app_runner_rbac_count

  metadata {
    name      = "app-runner-ingress-read"
    namespace = "ingress-nginx"
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding_v1" "app_runner_ingress_read" {
  count = local.app_runner_rbac_count

  metadata {
    name      = "app-runner-ingress-read"
    namespace = "ingress-nginx"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app_runner_ingress_read[0].metadata[0].name
  }

  subject {
    kind      = "User"
    name      = var.app_runner_sa_email
    api_group = "rbac.authorization.k8s.io"
  }
}
