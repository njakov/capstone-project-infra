# Advanced Capstone Project: Cloud Infrastructure


This repository is a part of the DevOps Capstone Project for DevOps Internship in GridDynamics.

* This repository contains the **Infrastructure as Code (IaC)** implementation: it uses **Terraform** to provision a scalable, secure, and automated Kubernetes-based architecture on **Google Cloud Platform (GCP)**.
* The infrastructure is designed to host a Java Spring PetClinic application with high availability, automated CI/CD pipelines, and strict security practices.

Here, you can find the code for:
* Creating Self-Hosted GitHub Actions Runners (infra GCE + ARC foundation)
* Dev & Production Environment Provisioning
* Custom Modules Repository
* Architecture Diagram
* Architecture Decision Records ([docs/adr](docs/adr/))

For more details, please refer to:
* [Capstone Project Description ](.github/assets/Capstone%20advanced%20k8s%20project.pdf)
* [Spring-Petclinic App Repository](https://github.com/njakov/capstone-project-app)
* [ADR 001: Runner isolation](docs/adr/001-runner-isolation.md)
* [Monitoring scrape path](docs/monitoring.md)

## Project Overview

* **Cloud Provider:** Google Cloud Platform (GCP) 
* **Infrastructure Tool:** Terraform (State stored in GCS with versioning)
* **Orchestrator:** Google Kubernetes Engine (GKE) - Private Cluster
* **Database:** Cloud SQL (MySQL) - Private IP only
* **Secrets Management:** Google Secret Manager
* **CI/CD:** GitHub Actions — infra on GCE runners (`self-hosted,infra,{env}`); app CI on ARC (ephemeral) after cutover
* **Configuration Management:** Helm 
* **Monitoring:** Prometheus & Grafana (via Helm) 

## Project Demo
![Project Demo](./.github/assets/monitoring.gif) 

### Production
![Production](./.github/assets/prod.png)
### Development
![Development](./.github/assets/dev.png)
---

## Repository Structure

```text
├── .github/workflows/       # Infra CI (infra-pipeline.yml)
├── docs/
│   ├── adr/                 # Architecture Decision Records
│   ├── arc-cutover.md       # ARC cutover notes
│   └── monitoring.md        # Prometheus/Grafana scrape & demo path
├── environments/
│   ├── bootstrap/           # Infra VPC + app VPC + peering + infra runner
│   ├── dev/                 # Development environment entry point
│   └── prod/                # Production environment entry point
├── modules/                 # Reusable Terraform modules
│   ├── artifact-registry/   # Docker container storage
│   ├── cloud-sql/           # Managed MySQL database
│   ├── gke/                 # Kubernetes Cluster configuration
│   ├── identity/            # App SA + ARC app-runner SA (Workload Identity)
│   ├── middleware/          # Helm charts (Ingress, Prometheus)
│   ├── network/             # VPC, Subnets, Firewalls, NAT
│   ├── network-peering/     # Bidirectional VPC peering (infra ↔ app)
│   ├── runner/              # Infra-only self-hosted GitHub Actions runner VM
│   └── arc/                 # ARC controller + scale set + NetworkPolicies
├── scripts/                 # Bash scripts for setup and bootstrapping
└── .tfsec/                  # Security scanner configuration
``` 

## Architecture

The infrastructure follows a modular design with environment separation (`dev`, `prod`) and a bootstrap layer that splits **infra** and **app** networking.

See [ADR 001: Runner isolation](docs/adr/001-runner-isolation.md) for locked decisions, accepted risks, and references. Regenerate [`.github/assets/architecture-diagram.png`](.github/assets/architecture-diagram.png) after cutover to match this layout.

### Key Components
1.  **Network (`modules/network` + `modules/network-peering`):**
    * **App VPC:** private subnet + GKE secondary ranges (pods/services). Distinct CIDRs per env in the shared GCP project.
    * **Infra VPC:** private subnet for GCE infra runners only; IAP SSH scoped to the `infra-runner` tag.
    * **Peering:** bidirectional peering with custom-route import/export so infra runners reach the private GKE API.
    * **Cloud NAT:** private nodes/VMs egress without public IPs.
2.  **Compute (`modules/gke`, `modules/runner`, `modules/arc`):**
    * **GKE:** Private cluster with VPC-native networking. Master authorized networks include the app subnet **and** the infra runner subnet. Second node pool `runners` is tainted (`github.runner=true:NoSchedule`) and labeled `workload=github-runner` for ARC only.
    * **Infra GitHub Runner:** GCE VM `runner-vm-infra-{env}` on the infra VPC. Register with labels `self-hosted`, `infra`, `{env}`. Pre-installed: Docker (group-based socket access), Terraform, Helm, Java, TFSec/TFLint.
    * **ARC:** ephemeral app runners (`petclinic-arc-{env}`) in the same GKE cluster via `modules/arc`, using least-privilege `github-app-runner-sa-{env}` Workload Identity. Demo NetworkPolicies default-deny in `arc-runners` / `arc-systems` with DNS+HTTPS egress. Cutover steps: [docs/arc-cutover.md](docs/arc-cutover.md).
3.  **Database (`modules/cloud-sql`):**
    * Cloud SQL (MySQL 8.0) connected via Private Service Access (VPC Peering) on the **app** VPC.
    * Passwords are generated randomly and stored immediately in **Google Secret Manager**.
4.  **Security:**
    * **Workload Identity:** App pods in namespace `petclinic` use K8s SA `petclinic` mapped to `petclinic-sa-{env}` (binding `petclinic/petclinic`). ARC runners use a separate least-privilege GCP SA.
    * **IAM split:** infra SA can Terraform (including `projectIamAdmin`, documented); ARC app-runner SA can only write Artifact Registry and deploy to GKE — no state/network/IAM admin.
    * **Secret Manager:** Centralized management for DB credentials and URLs.

## Architecture Diagram
![Architecture Diagram](./.github/assets/architecture-diagram.png)


## Getting Started

### Prerequisites  

1.  **GCP Project:** You must have a Google Cloud Project ID (e.g., `my-gcp-project`).  
2.  **Google Cloud SDK:** Installed and authenticated locally.  
3.  **Terraform:** Installed (v1.16.0).

### Step 1: Initial GCP Setup  
Run the setup script to enable required APIs (KMS, Storage, IAM), create the Terraform State Bucket, and set up the Service Account with necessary permissions. 
 
```bash
chmod +x scripts/setup_gcp.sh
./scripts/setup_gcp.sh
```

*   **What this does:** This script executes create-bucket.sh to provision the GCS backend with versioning and setup-terraform-sa.sh to create the Service Account and assign IAM roles.
    

### Step 2: Bootstrap Environment (Networks & Infra Runner)

Before deploying the application infrastructure, bootstrap the environment. This layer creates the **infra VPC**, **app VPC**, **peering**, and the **infra-only** Self-Hosted Runner VM.

```bash
chmod +x scripts/bootstrap-env.sh
./scripts/bootstrap-env.sh <ENV-NAME>
```

*   **What this does:** Initializes Terraform in `environments/bootstrap` and applies the corresponding `.tfvars` file (e.g. `dev.tfvars`).
*   **Output:** `runner_ssh_command` and `runner_registration_labels` (`self-hosted,infra,{env}`).
*   **Manual step:** IAP SSH to the VM, switch to user `runner`, and register the GitHub Actions runner with those labels.
*   **Migration note:** Prefer destroy/recreate bootstrap for `dev` if refactoring existing state is painful; see the ADR.

### Step 3: Environment apply (GKE, middleware, ARC)

After the infra runner is registered, apply `environments/{dev,prod}` (via `infra-pipeline` or from the runner).

1. First apply with `enable_arc = true` and `arc_install_charts = false` creates the runner node pool and GitHub App **Secret Manager shells**.
2. Populate secret versions (App ID, installation ID, private key PEM) — see [docs/arc-cutover.md](docs/arc-cutover.md).
3. Set `arc_install_charts = true` and apply again to install the controller, scale set, and NetworkPolicies.
4. Confirm `petclinic-arc-{env}` appears under GitHub → Settings → Actions → Runners.

### Step 4: Configure GitHub Actions variables

Project identifiers are **not** secrets. Add these as repository (or environment) **Actions variables** under Settings → Secrets and variables → Actions → Variables:

*   `GCP_PROJECT_ID`: Your Project ID (e.g., `my-project-id`).
*   `GCP_REGION`: The region for resources (e.g., `europe-west1`).
*   `TF_STATE_BUCKET`: The GCS state bucket from Step 1 (e.g., `terraform-state-bucket-my-project-id`).

Keep authenticators as secrets (e.g. `TF_VAR_grafana_admin_password` when set). If you previously stored the three identifiers above as secrets, migrate them to variables and remove the secret copies so `infra-pipeline.yml` resolves `vars.*`.

### Retarget GCP project

When switching to a different GCP project:

1. Edit committed tfvars `project_id` (and `allowed_source_ranges` / CIDRs as needed) in `environments/bootstrap/{dev,prod}.tfvars` and `environments/{dev,prod}/terraform.tfvars`. Placeholder shapes live in the matching `*.tfvars.example` files.
2. Set GitHub Actions variables `GCP_PROJECT_ID`, `GCP_REGION`, and `TF_STATE_BUCKET` on this repo (and the matching `GCP_PROJECT_ID` / `GCP_REGION` vars on the app repo).
3. Run setup/bootstrap with `PROJECT_ID` unset so scripts read tfvars, or `export PROJECT_ID=...` to override.
4. Apply the env stack (`infra-pipeline`), then deploy the app from the app repo.

Operator convenience outputs after env apply: `app_sa_email`, `cloud_sql_connection_name` (CI uses deterministic names; outputs are for docs / local Helm).

CI/CD Pipelines
------------------

Infra apply runs only through **`infra-pipeline.yml`** on runners labeled `self-hosted` + `infra` + `{env}`.

### Main Infrastructure Pipeline (`infra-pipeline.yml`)

*   **Trigger:** Pushes to `main` (plans **dev**), or manual `workflow_dispatch` for `dev` / `prod` with `plan` / `apply` / `destroy`.
*   **Protection:** Production deployments are limited to the `main` branch. Apply uses the GitHub Environment gate and a plan artifact (no apply without a prior plan).
*   **Runner:** `[self-hosted, infra, dev|prod]` — must match the GCE infra runner registration labels.

Application build/release/deploy workflows live in the **[capstone-project-app](https://github.com/njakov/capstone-project-app)** repository (not this repo). After ARC cutover they target scale set names such as `petclinic-arc-dev` / `petclinic-arc-prod`.

### Google Cloud Platform 
![GCP](./.github/assets/gke.png)

### Application Deployment Pipelines (app repo)

| Workflow | Trigger | Description |
| :--- | :--- | :--- |
| **PR Release** (`pr-release.yml`) | Pull Request | Unit tests, static analysis, Trivy; builds to the **dev** registry. |
| **Main Release** (`main-release.yml`) | Push to `main` | SemVer tag after tests/scan, image push to the **prod** registry. |
| **Manual Deploy** (`manual-deploy.yml`) | Manual Dispatch | Helm deploy of a chosen version to the target environment. |

## Tools & Technologies Used

| Category | Tool | Description |
| :--- | :--- | :--- |
| **IaC** | Terraform | Infrastructure provisioning (v1.16.0). |
| **State** | GCS | Remote backend with versioning enabled. |
| **Container** | Docker / Kaniko | Packaging; ARC builds prefer Kaniko (non-privileged). |
| **Orchestration** | Kubernetes (GKE) | Container management with VPC-native networking. |
| **Charts** | Helm | Deploying Nginx Ingress and Prometheus stack. |
| **Security** | TFSec / TFLint | Static analysis for Terraform code. |
| **Secrets** | Secret Manager | Secure storage for Database credentials and URLs. |
| **CI/CD** | GitHub Actions | Infra on GCE; app on ARC ephemeral runners (after cutover). |

Monitoring & Middleware
--------------------------

The modules/middleware module installs essential shared services into the cluster via Helm:

1.  **Nginx Ingress Controller:** Managed via Helm as a `LoadBalancer` Service. Access is **source-restricted** via `allowed_source_ranges` in each environment's `terraform.tfvars` (operator IP or VPN CIDR) — not public-by-default (`0.0.0.0/0` is rejected). TLS / cert-manager is out of MVP scope; HTTP only is an accepted demo limit.

2.  **Kube Prometheus Stack:** Deploys Prometheus, Grafana, and Alertmanager into the `monitoring` namespace with demo-sized retention (`7d`) and a `10Gi` PVC. Prometheus discovers app `ServiceMonitor` / `PrometheusRule` CRs labeled `release: prometheus-community` in **all** namespaces (including `petclinic`). Grafana’s dashboard sidecar uses `searchNamespace: ALL` so the app chart’s Micrometer dashboard ConfigMap loads from the `petclinic` namespace.

**App scrape path (primary):** Prometheus scrapes Spring Actuator `/actuator/prometheus` on the PetClinic Service port `http-web` (→ container `8080`). The JMX agent on container `:9093` is optional/local only and is **not** a cluster scrape target. Full walkthrough, Grafana password notes, and Gate H demo steps: [docs/monitoring.md](docs/monitoring.md).

**Grafana admin:** if `grafana_admin_password` is unset, the chart default is `admin` / `prom-operator`. Prefer a one-time secret via `TF_VAR_grafana_admin_password` (do not commit).

![Monitoring](./.github/assets/monitoring-alerts.gif) 

Important Notes
------------------

*   **State Management:** The Terraform state is stored remotely in a GCS bucket.
    
*   **Ingress access:** `allowed_source_ranges` in each environment's `terraform.tfvars` limits who can reach the Ingress LoadBalancer. Update it if your public IP changes.
    
*   **Security:** Public access to the database is disabled. The Cloud SQL instance only allows connections via Private Service Access (VPC Peering).
    
*   **SSH Access:** SSH to the infra runner is IAP-only, scoped to the `infra-runner` network tag.
    
*   **Runner labels:** Register infra runners as `self-hosted,infra,{env}` or the infra pipeline will not pick them up.
    
*   **Cost:** This infrastructure creates real resources (GKE Cluster, Load Balancers, Cloud SQL). Remember to run the **Destroy** workflow.
