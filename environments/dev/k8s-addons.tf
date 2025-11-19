# environments/dev/k8s-addons.tf

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

# --- 2. GCP Provider for CSI Driver (Final, Correct Configuration) ---
resource "helm_release" "csi_gcp_provider" {
  name = "secrets-store-csi-driver-provider-gcp"

  # CRITICAL FIX: The correct URL for the Helm chart index.
  repository = "https://googlecloudplatform.github.io/secrets-store-csi-driver-provider-gcp/"

  # The chart name is confirmed to be the full name based on the uploaded source code.
  chart      = "secrets-store-csi-driver-provider-gcp"
  version    = "1.4.2"
  namespace  = "kube-system"
  depends_on = [helm_release.csi_driver]
}