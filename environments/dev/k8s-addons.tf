# --- 1. Secrets Store CSI Driver Installation (via Helm) ---
# This is the base component that manages the volume mount
resource "helm_release" "csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = "1.3.0"
  namespace  = "kube-system"
  depends_on = [module.gke]
}

# --- 2. GCP Provider for CSI Driver ---
# This is the specific connector that allows the CSI driver to talk to Google Secret Manager
resource "helm_release" "csi_gcp_provider" {
  name       = "secrets-store-csi-driver-provider-gcp"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver-provider-gcp/charts"
  chart      = "secrets-store-csi-driver-provider-gcp"
  version    = "1.4.2"
  namespace  = "kube-system"
  depends_on = [helm_release.csi_driver]
}