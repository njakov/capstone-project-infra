# 1. Nginx Ingress Controller
# This provides the "nginx" class your App requests in ingress.yaml
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    }
  ]

  # Wait for the GKE cluster to be ready
  depends_on = [module.gke]
}

# 2. Prometheus Stack (Monitoring)
# This satisfies the requirement to "Install monitoring agents" and "Visualize metrics"
resource "helm_release" "kube_prometheus_stack" {
  name             = "prometheus-community"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  depends_on = [module.gke]
}