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

# Docker socket: group access only (never chmod 666).
# Create a dedicated runner user and add it to the docker group.
groupadd -f docker
if ! id -u runner &>/dev/null; then
    useradd --create-home --shell /bin/bash --groups docker runner
else
    usermod -aG docker runner
fi
systemctl enable --now docker || true
# Ensure socket is owned by root:docker with restrictive mode once Docker is up
if [ -S /var/run/docker.sock ]; then
    chown root:docker /var/run/docker.sock
    chmod 660 /var/run/docker.sock
fi

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
    apt-get install -y terraform=1.16.3-1
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

# 6. Install Helm, TFLint, and Trivy from pinned archives.
# Checksums are the upstream release digests. Do not pipe remote installers.
install_pinned_archive() {
  local url="$1"
  local sha256="$2"
  local archive_name="$3"
  local binary_name="$4"
  local workdir archive binary

  workdir="$(mktemp -d)"
  archive="${workdir}/${archive_name}"
  curl -fsSL -o "${archive}" "${url}"
  echo "${sha256}  ${archive}" | sha256sum -c -
  case "${archive_name}" in
    *.zip) unzip -q "${archive}" -d "${workdir}" ;;
    *.tar.gz|*.tgz) tar -xzf "${archive}" -C "${workdir}" ;;
    *)
      echo "Unsupported archive ${archive_name}" >&2
      rm -rf "${workdir}"
      exit 1
      ;;
  esac
  binary="$(find "${workdir}" -type f -name "${binary_name}" -print -quit)"
  if [ -z "${binary}" ]; then
    echo "Binary ${binary_name} not found in ${url}" >&2
    rm -rf "${workdir}"
    exit 1
  fi
  install -m 0755 "${binary}" "/usr/local/bin/${binary_name}"
  rm -rf "${workdir}"
}

if ! command -v helm &> /dev/null; then
  echo "Installing Helm v3.17.3..."
  install_pinned_archive \
    "https://get.helm.sh/helm-v3.17.3-linux-amd64.tar.gz" \
    "ee88b3c851ae6466a3de507f7be73fe94d54cbf2987cbaa3d1a3832ea331f2cd" \
    "helm.tgz" \
    "helm"
fi

if ! command -v tflint &> /dev/null; then
  echo "Installing TFLint v0.58.1..."
  install_pinned_archive \
    "https://github.com/terraform-linters/tflint/releases/download/v0.58.1/tflint_linux_amd64.zip" \
    "2fea1af8e8602d4d9e4253a588ac66f17bf36152cafb51f4d929b8bc6335e740" \
    "tflint.zip" \
    "tflint"
fi

if ! command -v trivy &> /dev/null; then
  echo "Installing Trivy v0.74.0..."
  install_pinned_archive \
    "https://github.com/aquasecurity/trivy/releases/download/v0.74.0/trivy_0.74.0_Linux-64bit.tar.gz" \
    "2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a" \
    "trivy.tar.gz" \
    "trivy"
fi

# 7. Configure Docker Auth
echo "Configuring Docker Auth..."
gcloud auth configure-docker --quiet

echo "Installation Complete! Runner is ready."
echo "Register the GitHub Actions runner as user 'runner' with labels: self-hosted,infra,<env>"
echo "IAP SSH then: sudo -iu runner"
