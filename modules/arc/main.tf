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

  # Wait loop for the rootless BuildKit sidecar (UID 1000). The runner writes
  # a request file on the shared emptyDir; this loop runs buildctl-daemonless
  # and leaves a docker-archive tarball for Trivy and crane. No registry push.
  buildkit_wait_script = <<EOT
set -eu
mkdir -p /buildkit-work/requests /home/user/.local/tmp /run/user/1000
while true; do
  if [ -f /buildkit-work/requests/build.req ]; then
    CONTEXT=$(sed -n 's/^CONTEXT=//p' /buildkit-work/requests/build.req)
    DOCKERFILE=$(sed -n 's/^DOCKERFILE=//p' /buildkit-work/requests/build.req)
    TAR_PATH=$(sed -n 's/^TAR_PATH=//p' /buildkit-work/requests/build.req)
    IMAGE_NAME=$(sed -n 's/^DESTINATION=//p' /buildkit-work/requests/build.req)
    rm -f /buildkit-work/requests/build.req /buildkit-work/requests/build.exit
    DOCKERFILE_DIR=$(dirname "$DOCKERFILE")
    DOCKERFILE_NAME=$(basename "$DOCKERFILE")
    set +e
    /usr/bin/buildctl-daemonless.sh build --frontend dockerfile.v0 --local context="$CONTEXT" --local dockerfile="$DOCKERFILE_DIR" --opt filename="$DOCKERFILE_NAME" --output type=docker,dest="$TAR_PATH",name="$IMAGE_NAME" > /buildkit-work/build.log 2>&1
    echo $? > /buildkit-work/requests/build.exit.tmp
    mv /buildkit-work/requests/build.exit.tmp /buildkit-work/requests/build.exit
    set -e
  fi
  sleep 1
done
EOT
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
  from = kubernetes_secret_v1.github_app

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
        metadata = {
          annotations = {
            # Ubuntu 24.04 AppArmor still confines the container without this.
            "container.apparmor.security.beta.kubernetes.io/buildkit" = "unconfined"
          }
        }
        spec = {
          serviceAccountName = var.runner_k8s_sa_name
          nodeSelector       = var.runner_node_selector
          tolerations        = var.runner_tolerations
          # Default container mode (chart 0.10.1): a container not named "runner"
          # is emitted as written, and volumes pass through. Do not set
          # containerMode dind or kubernetes; those use different volume helpers.
          # Runner stays UID 0 because run-helper.sh exits without
          # RUNNER_ALLOW_RUNASROOT. BuildKit runs as UID 1000 in its own container.
          volumes = [
            {
              name     = "buildkit-work"
              emptyDir = {}
            },
            {
              # Explicit emptyDir: the image VOLUME is mounted nosuid,nodev and
              # rootless BuildKit cannot use it.
              name     = "buildkit-state"
              emptyDir = {}
            }
          ]
          containers = [
            {
              name = "runner"
              # Chart stays 0.10.1. Image is actions-runner 2.337.0 (2026-08-26),
              # pinned to that tag's multi-arch index digest.
              # run-helper.sh exits 1 as uid 0 unless RUNNER_ALLOW_RUNASROOT is set.
              image   = "ghcr.io/actions/actions-runner@sha256:e5496277be5d09bc968b3d64911b74e219ac4a3f2edce956a3ecf9271bea1ef4"
              command = ["/home/runner/run.sh"]
              env = [
                {
                  name  = "RUNNER_ALLOW_RUNASROOT"
                  value = "1"
                }
              ]
              securityContext = {
                runAsUser = 0
              }
              volumeMounts = [
                {
                  name      = "buildkit-work"
                  mountPath = "/buildkit-work"
                }
              ]
            },
            {
              name = "buildkit"
              # v0.33.0-rootless multi-arch index, resolved 2026-09-22.
              # UID 1000, no privileged flag, no Docker socket. Ubuntu 24.04
              # blocks remount of / unless /proc is unmasked and SYS_ADMIN can
              # create the user namespace.
              image = "moby/buildkit@sha256:80b15f0735e87bab7bf59ec4d695dfb4a7cfb25521cf56dc75d6f256285b63ef"
              command = [
                "/bin/sh",
                "-c",
                local.buildkit_wait_script,
              ]
              env = [
                {
                  name  = "BUILDKITD_FLAGS"
                  value = "--oci-worker-no-process-sandbox"
                },
                {
                  name  = "HOME"
                  value = "/home/user"
                },
                {
                  name  = "USER"
                  value = "user"
                },
                {
                  name  = "XDG_RUNTIME_DIR"
                  value = "/run/user/1000"
                }
              ]
              securityContext = {
                runAsUser                = 1000
                runAsGroup               = 1000
                allowPrivilegeEscalation = true
                privileged               = false
                procMount                = "Unmasked"
                seccompProfile = {
                  type = "Unconfined"
                }
                appArmorProfile = {
                  type = "Unconfined"
                }
                capabilities = {
                  add = [
                    "SYS_ADMIN",
                    "CHOWN",
                    "DAC_OVERRIDE",
                    "FOWNER",
                    "FSETID",
                    "SETGID",
                    "SETUID",
                    "SETFCAP",
                  ]
                }
              }
              volumeMounts = [
                {
                  name      = "buildkit-work"
                  mountPath = "/buildkit-work"
                },
                {
                  name      = "buildkit-state"
                  mountPath = "/home/user/.local/share/buildkit"
                }
              ]
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
# Primary isolation: default-deny in arc-runners; allow DNS, the metadata server,
# and TCP/443 and TCP/6443 to everywhere except the private app and infra CIDRs.
# The GKE master CIDR is not in that exception list. Pod-to-pod HTTP to
# PetClinic ClusterIPs is denied by omission.
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
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = var.https_egress_except_cidrs
        }
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = var.https_egress_except_cidrs
        }
      }
      ports {
        protocol = "TCP"
        port     = "6443"
      }
    }

    # Dataplane V2 applies egress policy to the metadata server. Workload Identity
    # and gcloud on runner pods use 169.254.169.254 TCP 80 and 988.
    egress {
      to {
        ip_block {
          cidr = "169.254.169.254/32"
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
      ports {
        protocol = "TCP"
        port     = "988"
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
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = var.https_egress_except_cidrs
        }
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = var.https_egress_except_cidrs
        }
      }
      ports {
        protocol = "TCP"
        port     = "6443"
      }
    }

    # Dataplane V2 applies egress policy to the metadata server. Workload Identity
    # and gcloud on controller pods use 169.254.169.254 TCP 80 and 988.
    egress {
      to {
        ip_block {
          cidr = "169.254.169.254/32"
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
      ports {
        protocol = "TCP"
        port     = "988"
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
