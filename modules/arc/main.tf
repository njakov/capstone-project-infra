# modules/arc — Actions Runner Controller (scale sets) + demo NetworkPolicies
#
# Two-step install (see docs/arc-cutover.md):
# 1. install_charts = false → Secret Manager shells + the arc-runners namespace.
#    External Secrets syncs those shells into Kubernetes secret arc-github-app.
# 2. Operator adds secret versions and waits until ExternalSecret arc-github-app is Ready.
#    Terraform must not read or own that secret: a refresh would write the PEM into state.
# 3. install_charts = true  → arc-systems namespace, WI SA, Helm, NetworkPolicies

locals {
  scale_set_name = coalesce(var.runner_scale_set_name, "${var.app_name}-arc-${var.env}")

  github_app_id_secret_id              = coalesce(var.github_app_id_secret_id, "arc-github-app-id-${var.env}")
  github_app_installation_id_secret_id = coalesce(var.github_app_installation_id_secret_id, "arc-github-app-installation-id-${var.env}")
  github_app_private_key_secret_id     = coalesce(var.github_app_private_key_secret_id, "arc-github-app-private-key-${var.env}")

  github_config_secret_name = "arc-github-app"
  controller_sa_name        = "arc-gha-runner-scale-set-controller"
}

# ------------------------------------------------------------------------------
# Secret Manager shells — always created; versions added by operator
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret" "github_app_id" {
  project   = var.project_id
  secret_id = local.github_app_id_secret_id

  replication {
    auto {}
  }

  labels = {
    purpose = "arc-github-app"
    env     = var.env
  }
}

resource "google_secret_manager_secret" "github_app_installation_id" {
  project   = var.project_id
  secret_id = local.github_app_installation_id_secret_id

  replication {
    auto {}
  }

  labels = {
    purpose = "arc-github-app"
    env     = var.env
  }
}

resource "google_secret_manager_secret" "github_app_private_key" {
  project   = var.project_id
  secret_id = local.github_app_private_key_secret_id

  replication {
    auto {}
  }

  labels = {
    purpose = "arc-github-app"
    env     = var.env
  }
}

# Resource-level accessor on the three GitHub App shells for the External Secrets GCP account.
resource "google_secret_manager_secret_iam_member" "github_app_id_access" {
  secret_id = google_secret_manager_secret.github_app_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.external_secrets_gcp_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "github_app_installation_id_access" {
  secret_id = google_secret_manager_secret.github_app_installation_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.external_secrets_gcp_sa_email}"
}

resource "google_secret_manager_secret_iam_member" "github_app_private_key_access" {
  secret_id = google_secret_manager_secret.github_app_private_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.external_secrets_gcp_sa_email}"
}

# ------------------------------------------------------------------------------
# arc-runners exists before charts so External Secrets can sync arc-github-app.
# Helm still references that secret name; Terraform does not manage the object.
# ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "arc_runners" {
  # Not gated on install_charts: External Secrets syncs arc-github-app here
  # before charts. count stays 1 so the [0] state address does not move.
  count = 1

  metadata {
    name = var.arc_runners_namespace
    labels = {
      "app.kubernetes.io/name"      = "arc-runners"
      "app.kubernetes.io/part-of"   = "actions-runner-controller"
      "kubernetes.io/metadata.name" = var.arc_runners_namespace
    }
  }
}

# ------------------------------------------------------------------------------
# arc-systems / WI SA / Helm / NetworkPolicies (when install_charts)
# ------------------------------------------------------------------------------
resource "kubernetes_namespace_v1" "arc_systems" {
  count = var.install_charts ? 1 : 0

  metadata {
    name = var.arc_systems_namespace
    labels = {
      "app.kubernetes.io/name"      = "arc-systems"
      "app.kubernetes.io/part-of"   = "actions-runner-controller"
      "kubernetes.io/metadata.name" = var.arc_systems_namespace
    }
  }
}

resource "kubernetes_service_account_v1" "arc_runner" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = var.runner_k8s_sa_name
    namespace = kubernetes_namespace_v1.arc_runners[0].metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = var.app_runner_gcp_sa_email
    }
    labels = {
      "app.kubernetes.io/name" = "arc-runner"
    }
  }
}

resource "helm_release" "arc_controller" {
  count = var.install_charts ? 1 : 0

  name      = "arc"
  chart     = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
  version   = var.chart_version
  namespace = kubernetes_namespace_v1.arc_systems[0].metadata[0].name
  timeout   = 600
  wait      = true

  values = [
    yamlencode({
      serviceAccount = {
        create = true
        name   = local.controller_sa_name
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.arc_systems]
}

# githubConfigSecret (arc-github-app) is synced by External Secrets, not Terraform.
# If a previous apply owned the secret, forget it without deleting the object.
removed {
  from = kubernetes_secret_v1.github_app[0]

  lifecycle {
    destroy = false
  }
}

resource "helm_release" "arc_runners" {
  count = var.install_charts ? 1 : 0

  name      = local.scale_set_name
  chart     = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
  version   = var.chart_version
  namespace = kubernetes_namespace_v1.arc_runners[0].metadata[0].name
  timeout   = 600
  wait      = true

  values = [
    yamlencode({
      githubConfigUrl    = var.github_config_url
      githubConfigSecret = local.github_config_secret_name
      runnerScaleSetName = local.scale_set_name
      minRunners         = var.min_runners
      maxRunners         = var.max_runners

      controllerServiceAccount = {
        namespace = var.arc_systems_namespace
        name      = local.controller_sa_name
      }

      template = {
        spec = {
          serviceAccountName = var.runner_k8s_sa_name
          nodeSelector       = var.runner_node_selector
          tolerations        = var.runner_tolerations
          # runAsUser 0: Kaniko executor (app CI) must unpack layers under /kaniko.
          # Prefer this over privileged DinD; still not a hard security domain (see ADR).
          containers = [
            {
              name    = "runner"
              image   = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
              securityContext = {
                runAsUser = 0
              }
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_service_account_v1.arc_runner,
  ]
}

# ------------------------------------------------------------------------------
# Demo-quality NetworkPolicies (Dataplane V2)
# Primary isolation: default-deny in arc-runners; allow DNS + HTTPS (+ apiserver).
# Pod-to-pod HTTP to PetClinic ClusterIPs is denied by omission.
# ------------------------------------------------------------------------------
resource "kubernetes_network_policy_v1" "arc_runners_default_deny" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.arc_runners[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "arc_runners_allow_egress" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "allow-dns-https-egress"
    namespace = kubernetes_namespace_v1.arc_runners[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    egress {
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      ports {
        protocol = "TCP"
        port     = "6443"
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.arc_runners_default_deny]
}

resource "kubernetes_network_policy_v1" "arc_systems_default_deny" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.arc_systems[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy_v1" "arc_systems_allow_egress" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "allow-dns-https-egress"
    namespace = kubernetes_namespace_v1.arc_systems[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    egress {
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      ports {
        protocol = "TCP"
        port     = "6443"
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.arc_systems_default_deny]
}

resource "kubernetes_network_policy_v1" "arc_runners_allow_from_controller" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "allow-from-arc-systems"
    namespace = kubernetes_namespace_v1.arc_runners[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.arc_systems_namespace
          }
        }
      }
    }

    # Listener + runner pods share arc-runners; default-deny would block them otherwise.
    ingress {
      from {
        pod_selector {}
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.arc_runners_default_deny]
}

resource "kubernetes_network_policy_v1" "arc_systems_allow_from_self" {
  count = var.install_charts ? 1 : 0

  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace_v1.arc_systems[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {}
      }
    }
  }

  depends_on = [kubernetes_network_policy_v1.arc_systems_default_deny]
}
