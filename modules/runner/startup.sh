#!/bin/bash
set -e

echo "Starting Runner Setup on $(hostname)..."

# 1. Install Base Dependencies
echo "Installing Base Dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release unzip software-properties-common git jq wget apt-transport-https

# 2. Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

chmod 666 /var/run/docker.sock

if ! command -v java &> /dev/null; then
  echo "Installing Java 25..."
  # Download the latest JDK 25 Debian package directly from Oracle
  # Reference: https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb
  wget https://download.oracle.com/java/25/latest/jdk-25_linux-x64_bin.deb -O /tmp/jdk-25_linux-x64_bin.deb
  
  # Install using apt to resolve dependencies automatically
  apt-get install -y /tmp/jdk-25_linux-x64_bin.deb
  
  # Cleanup
  rm /tmp/jdk-25_linux-x64_bin.deb
  
  echo "Java installed successfully:"
  java -version
fi

# 3. Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update
    apt-get install -y terraform
fi

# 4. Install OpenJDK 25
if ! command -v java &> /dev/null; then
  echo "Installing OpenJDK 25..."
  add-apt-repository -y universe
  apt-get update
  apt-get install -y openjdk-25-jdk-headless
  
  echo "Java Version Check:"
  java -version
fi

# 5. Add Google Cloud SDK Repo & Install Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Adding Google Cloud SDK Repo..."
    # Add the GPG key
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    
    # Add the repository source
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list

    # Update and Install
    apt-get update
    echo "Installing Kubectl and Auth Plugin..."
    apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl
fi

# 6. Install Helm
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 7. Install Security Scanners
echo "Installing Scanners..."
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash

# 7. Configure Docker Auth
echo "Configuring Docker Auth..."
gcloud auth configure-docker --quiet

echo "✅ Installation Complete! Runner is ready."