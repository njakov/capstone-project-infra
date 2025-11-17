#!/bin/bash

set -e

echo "Starting GCP setup..."

echo "Executing create-bucket.sh..."
chmod +x create-bucket.sh
./create-bucket.sh

echo "Executing create-service-account.sh..."
chmod +x setup-terraform-sa.sh
./setup-terraform-sa.sh

echo "All setup scripts have been executed successfully!"