#!/bin/bash

# --- Configuration ---
BUCKET_NAME="capstone-tfstate-bucket-njakov"
PROJECT_ID="gd-gcp-internship-devops"
LOCATION="europe-west1"

set -e

echo "Creating GCS bucket: $BUCKET_NAME in project $PROJECT_ID..."

# Command 1: Create the globally unique GCS bucket.
# Used uniform-bucket-level-access to prevent ACL access.
gcloud storage buckets create "gs://$BUCKET_NAME" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --uniform-bucket-level-access

echo "Bucket created successfully."

echo "Enabling versioning on bucket: $BUCKET_NAME..."

gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

echo "Versioning enabled successfully. Your backend bucket is ready."

