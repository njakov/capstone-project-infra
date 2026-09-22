# modules/middleware/main.tf

locals {
  grafana_values = merge(
    {
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL"
        }
      }
    },
    var.grafana_admin_password != null ? {
      adminPassword = var.grafana_admin_password
    } : {}
  )
}

# Nginx Ingress Controller
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  values = [
    yamlencode({
      controller = {
        service = {
          type                     = "LoadBalancer"
          loadBalancerSourceRanges = var.allowed_source_ranges
        }
      }
    })
  ]
}

# Prometheus Stack
# Discovers app ServiceMonitors / PrometheusRules labeled release=prometheus-community
# (including the petclinic namespace) and loads Grafana dashboards from any namespace.
resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus-community"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.prometheus_retention
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
          # Match ServiceMonitors / PrometheusRules with label release=<helm release name>
          serviceMonitorSelectorNilUsesHelmValues = true
          serviceMonitorNamespaceSelector         = {}
          ruleSelectorNilUsesHelmValues           = true
          ruleNamespaceSelector                   = {}
          podMonitorSelectorNilUsesHelmValues     = true
          podMonitorNamespaceSelector             = {}
        }
      }
      grafana = local.grafana_values
      # GKE runs kube-dns, which does not listen on CoreDNS port 9153.
      # The chart default ServiceMonitor stays 0/2 down, so leave it off.
      coreDns = {
        enabled = false
      }
      alertmanager = {
        # Demo path: alerts visible in Prometheus / Alertmanager UI.
        # Optional external webhook (Slack/email) is out of MVP scope — see docs/monitoring.md.
        enabled = true
      }
    })
  ]
}
