# Local bootstrap must run as terraform-sa (keyless impersonation), not as the
# human Owner/Editor. Day-2 env applies use the GCE runner SA instead — see ADR 001.
provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = "terraform-sa@${var.project_id}.iam.gserviceaccount.com"
}
