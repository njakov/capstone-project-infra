terraform {
  backend "gcs" {
    # bucket and prefix are passed at init time:
    #   -backend-config="bucket=terraform-state-bucket-${PROJECT_ID}"
    #   -backend-config="prefix=bootstrap/${ENV}"
  }
}
