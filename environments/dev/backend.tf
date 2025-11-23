terraform {
  backend "gcs" {
    bucket = "terraform-state-bucket-teak-advice-475415-i2"
    prefix = "env/dev"
  }
}