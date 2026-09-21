# ADR 001: Runner isolation (infra GCE + in-cluster ARC)

**Status:** Accepted  
**Date:** 2026-09-21  
**Repo:** `capstone-project-infra`

## Context

Previously a single GCE VM lived in the **app VPC** and ran both Terraform (infra apply) and application CI/CD (Docker build, Helm deploy). That colocates a powerful Terraform identity with app build/deploy, widens blast radius, and makes it hard to teach least-privilege runner design.

This capstone must showcase private networking and runner isolation on a **trial Gmail billing account** (no org, no folders, no deny policies). The hard constraints:

1. **Isolation is a project boundary.** Dev and prod are separate GCP projects. In-project IAM Conditions on `container.admin` are not a substitute for a second project.
2. **Bootstrap is chicken-egg only.** Local `terraform-sa` creates the infra VPC, runner SA/VM, and workload SAs + project IAM. It must not create the app VPC, GKE, or SQL. After bootstrap, `terraform-sa` is **disabled**.
3. **Day-2 must not be project IAM admin.** The GCE infra runner applies env Terraform (app VPC, peering, GKE, SQL, WI). It keeps workload `*admin` roles and `networkAdmin` inside its project, but loses `projectIamAdmin` and project-level SA admin/user so it cannot rewrite project IAM or hijack `terraform-sa`.

App CI still runs as **ARC ephemeral runners** in the same env GKE cluster (privilege reduction within the cluster, not a second GKE). Compromised ARC cannot touch Terraform state or the other project's runners.

## Decision

| Concern | Choice |
|---------|--------|
| Env isolation | **One GCP project per env.** Dev keeps existing ID `project-62ebde90-46b7-4e70-b59` (immutable; display name `PetClinic Dev`). Prod is a **new** project (display name `PetClinic Prod`; ID `petclinic-gke-prod`). Never reuse the dev UUID. |
| Infra plane | **Per-env infra VPC + GCE runner** (`runner-vm-infra-{env}`), labels `self-hosted`, `infra`, `{env}`, machine type **`e2-medium`** |
| App CI plane | **ARC ephemeral runner scale sets** in the **same** env GKE cluster (`modules/arc`, scale set `petclinic-arc-{env}`) |
| Cluster topology | Same GKE as the app — **privilege reduction**, not a second security domain |
| Bootstrap scope | **Infra VPC + NAT + IAP SSH + runner SA/VM + `bootstrap-iam` only.** No app VPC. No peering. |
| App network | **Env apply** creates app VPC + both peering legs (infra via data source), then GKE. Runner `networkAdmin` is the accepted cost of bare-min bootstrap. |
| In-cluster isolation | Dedicated namespaces (`arc-systems` / `arc-runners`), tainted `runners` node pool, demo-quality NetworkPolicies, Workload Identity |
| Build strategy on ARC | **Kaniko** (non-privileged); no DinD in MVP |
| Infra CI path | Single apply path: [`infra-pipeline.yml`](../../.github/workflows/infra-pipeline.yml) on infra-labeled runners. Before `terraform init`, validate, plan, apply, and destroy fail closed unless `environments/{env}/terraform.tfvars` exists and `project_id` parses. The state bucket is `terraform-state-bucket-${project_id}`. GitHub Environment on those jobs is for deployment protection, not for `GCP_PROJECT_ID` / `GCP_REGION` / `TF_STATE_BUCKET` |

### CIDR plan (non-overlapping; distinct even across projects)

| Network | Dev | Prod |
|---------|-----|------|
| App subnet | `10.10.0.0/24` | `10.11.0.0/24` |
| Pods / services | `10.20.0.0/16` / `10.30.0.0/16` | `10.21.0.0/16` / `10.31.0.0/16` |
| GKE master | `172.16.0.0/28` | `172.16.0.16/28` |
| Infra subnet | `10.50.0.0/24` | `10.51.0.0/24` |

Infra ↔ app VPC peering (env-owned) still connects the two VPCs. Control-plane access for Terraform is the GKE **DNS endpoint**, not exported custom routes: peering is not transitive, and Regular-channel clusters publish the control plane over Private Service Connect. `allow_external_traffic` makes that name reachable from the infra runner via Private Google Access. Access is Google IAM only (`container.clusters.connect`). Kubernetes ServiceAccount tokens and client certificates stay disabled on that name (`enable_k8s_tokens_via_dns` and `enable_k8s_certs_via_dns` are false); Helm and Terraform send the runner's Google access token. VPC Service Controls are unavailable on this trial account (no organization), so the DNS name has no network allowlist. `enable_private_nodes` and `enable_private_endpoint` stay true, and IP endpoints stay enabled. Helm and the Kubernetes provider use `https://<dns endpoint>` and omit `cluster_ca_certificate` (the DNS name presents a Google-managed certificate; passing the cluster CA makes TLS fail). `master_authorized_networks_config` still lists the app subnet and the infra subnet for the IP endpoint.

### Env sizing (dev cheaper / zonal; prod shows real HA)

| Layer | Dev | Prod |
|-------|-----|------|
| GKE control plane | **Zonal** (`europe-west1-c`). Not HA — accepted. Cluster fee covered by GKE free tier. | **Regional** (`europe-west1`). GKE HA screenshot. |
| App node pool | **1 zone** (`europe-west1-c`), min 1 / max 2 **per zone**, `e2-standard-2` | **2 zones** (`europe-west1-c`, `europe-west1-d`), min 1 / max 2 **per zone**, `e2-standard-2`. Not 3 zones. |
| ARC runner pool | Keep, min 0, `e2-standard-4` | Pool min 0; `arc_install_charts = false` unless a screenshot needs ARC |
| Cloud SQL | `db-f1-micro`, **`ZONAL`** | **`db-g1-small`, `REGIONAL`** from the start (no f1-micro HA pivot) |
| GCE infra runner | **`e2-medium`** (Terraform only; no Docker builds) | Same |
| Prometheus | 7d / 10Gi. If MemoryPressure on the single node, bump **machine type** (one `e2-standard-4`), not zone count. | Same defaults OK on two nodes |
| App replicas / HPA | 1–2 replicas, no HPA | 2 replicas if shown; no HPA |

### Trial runtime

- Dev live **up to ~1 week**. Prod is a **2–3 day screenshot window**, then destroy **env first** (regional GKE fee ticks from cluster create until delete), then bootstrap.
- First prod env apply budgets **45–90 minutes** (regional GKE + SQL HA + VPC + peering + Helm).
- Do not leave both stacks always-on. Estimated burn ~$60 combined vs $300 credit (list-price, europe-west1); confirm Billing balance before the prod window.

### IAM split

| Identity | Purpose | Notable roles |
|----------|---------|---------------|
| `terraform-sa` (local only) | Chicken-egg **bootstrap** from a laptop (optional break-glass). **Not** used by `infra-pipeline`. Locked after bootstrap by **disabling the SA**. | `networkAdmin`, `instanceAdmin.v1`, `securityAdmin`, `serviceAccountAdmin`, **conditioned** `projectIamAdmin` (`modifiedGrantsByRole` allow-list), `serviceUsageConsumer`; bucket `storage.objectAdmin` only. **No** project-level `serviceAccountUser`, **no** `container.admin` / `cloudsql.admin` / `secretmanager.admin` / `artifactregistry.admin`, **no** bucket `storage.admin`. Operator gets `roles/iam.serviceAccountTokenCreator` only — no SA JSON keys. |
| `github-infra-runner-sa-{env}` (GCE) | Day-2 Terraform apply (`infra-pipeline.yml`) | Project: `networkAdmin`, `container.admin`, `cloudsql.admin`, `secretmanager.admin`, `artifactregistry.admin`, `serviceUsageConsumer`; bucket `objectAdmin`. **No** `projectIamAdmin`, **no** project-level `serviceAccountAdmin` / `serviceAccountUser`. Resource-level (bootstrap D6): `infraRunnerWorkloadIdentityAdmin` on the app, app-runner, and external-secrets accounts, conditioned so `setIamPolicy` may only change `roles/iam.workloadIdentityUser`; `serviceAccountUser` on the node SA. |
| `github-app-runner-sa-{env}` (WI → ARC) | App build/deploy only | `artifactregistry.writer`, custom role `arcAppDeploy` (`container.clusters.get`, `container.clusters.getCredentials`, `container.clusters.connect`, `container.namespaces.get`). Kubernetes RBAC is a Role in `petclinic` plus get/list Services in `ingress-nginx`. **No** `container.developer`, **no** `container.secrets.*`, **no** namespace create/update, **no** binding in `arc-runners`, **no** `projectIamAdmin`, **no** state admin, **no** `networkAdmin`, **no** `secretmanager.admin` |

**Binder allow-list** (CEL on terraform-sa `projectIamAdmin`): workload grant roles only (`networkAdmin`, `container.admin`, `cloudsql.admin`, `secretmanager.admin`, `artifactregistry.admin`, `serviceUsageConsumer`, log/metric writers, AR reader/writer, `container.developer`, `cloudsql.client`, `projects/<project>/roles/arcAppDeploy`). `container.developer` stays on the list so bootstrap can revoke the old app-runner binding. It is not granted to any member. Off-list roles (incl. `owner`, `projectIamAdmin`, SA admin/user) → fix Terraform, **do not widen CEL**. Cleanup of off-list roles is Owner-only.

**Auth model:** keyless. Local bootstrap = user ADC + impersonate `terraform-sa` (`GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` + `environments/bootstrap/provider.tf`). `setup-terraform-sa.sh` is the **only** IAM writer; `bootstrap-env.sh` impersonates + apply only (fail closed if terraform-sa is disabled). After a successful apply it runs `scripts/lock-terraform-sa.sh` and disables the SA; `set -e` skips the lock when apply fails. Break-glass stays in that script: enable the SA, re-run bootstrap, lock again. Day-2 CI = GCE metadata credentials for `github-infra-runner-sa-{env}` (not `terraform-sa`, not GitHub→GCP OIDC).

**Negative IAM tests** (teaching demo; `scripts/negative-iam-tests.sh`): terraform-sa cannot bind `roles/owner` or create GKE/SQL; runner cannot `setIamPolicy` on `terraform-sa`, cannot bind `roles/iam.serviceAccountKeyAdmin` on the workload service accounts, and cannot mint keys on those accounts, including `external-secrets-{env}`. Expect `PERMISSION_DENIED`.

**Who creates what:**

| Stage | Creates |
|-------|---------|
| `setup_gcp` (human Owner) | State bucket; terraform-sa + conditioned IAM |
| Bootstrap (as terraform-sa) | Infra VPC/NAT/IAP; runner SA + VM; workload SAs + project IAM; D6 resource-level grants → then **disable terraform-sa** |
| Env apply (as runner) | App VPC + peering; GKE / SQL / AR / middleware / ARC; WI + secret accessor IAM only (no `google_project_iam_*`) |

### Honest residuals

| Residual | Why it remains |
|----------|----------------|
| Runner `networkAdmin` + four `*admin` roles **inside its project** | Isolation is the **other project**, not in-project narrowing of those admins |
| D6 custom role includes `setIamPolicy` | The binding condition allows only `roles/iam.workloadIdentityUser`. Key admin and token-creator grants are denied. `terraform-sa` still has project `serviceAccountAdmin` until it is disabled |
| State + `secretmanager.admin` | DB passwords available to the infra runner **by design** |
| Human Gmail user stays Owner | Real break-glass; never put `roles/owner` on an SA |

### Honest tradeoff

| Gain | Cost |
|------|------|
| Bootstrap is chicken-egg; terraform-sa cannot touch GKE/SQL | First env apply creates the app VPC and peering; Terraform reaches the control plane through the DNS endpoint |
| Runner cannot rewrite project IAM or hijack terraform-sa | Runner owns app VPC (`networkAdmin`). D6 `setIamPolicy` may only change `roles/iam.workloadIdentityUser` |
| Dev runner cannot touch prod | Second project + second bootstrap for 2–3 days |
| Dev is cheaper / zonal; prod shows real HA | Two GKE topologies in one module (`cluster_location` on cluster + both node pools) |

## Consequences

- Bootstrap creates **one** infra VPC + runner + workload IAM; first infra runner still needs a **local** bootstrap that **impersonates `terraform-sa`**. Day-2 applies use **`github-infra-runner-sa-{env}`**, not `terraform-sa`.
- App VPC + peering move to env state. Applying slim bootstrap onto old state that still owns `module.app_network` **deletes the app VPC** — destroy env then bootstrap before migrating.
- Infra workflows must use `runs-on: [self-hosted, infra, {env}]`. `project_id` and `region` come from `environments/{env}/terraform.tfvars`. The shared checkout guard fails before `terraform init` when that file is missing or `project_id` cannot be parsed, and the state bucket is `terraform-state-bucket-${project_id}`. CI does not read `GCP_PROJECT_ID`, `GCP_REGION`, or `TF_STATE_BUCKET` from GitHub. Delete those variables at repository scope after any Environment copies exist, then delete the `dev` and `prod` Environment copies. The GitHub Environment on validate, plan, apply, and destroy is for deployment protection. Required reviewers cannot be set from the workflow; add them on the `prod` Environment (operator step). They gate every prod job, including plan and destroy.
- App workflows use ARC scale set names (`petclinic-arc-dev` / `petclinic-arc-prod`) and build images with **Kaniko** (no DinD).
- ARC runner pods run as UID 0 so the Kaniko executor can unpack layers under `/kaniko` (still no privileged Docker socket).
- Compromised ARC with deploy rights can still change Deployments **in that cluster**; this is accepted for the demo.
- Docker on the GCE infra VM (if present) uses the `docker` group (`runner` user) — never world-writable socket (`chmod 666`). Day-2 infra path is Terraform-only on `e2-medium`.
- App CI trusts GKE Workload Identity on ARC pods (not GitHub→GCP OIDC / `id-token`).

## Accepted risks (explicit)

- No org / folders / deny policies on trial Gmail
- Same GKE cluster for app workloads and ARC runners (within each project)
- Runner retains `networkAdmin` + workload `*admin` **inside** its project
- D6 `setIamPolicy` is limited to `roles/iam.workloadIdentityUser`. `terraform-sa` can still mint keys until `lock-terraform-sa.sh` disables it
- Prometheus may force a bigger **single** dev node (machine type, not zone count)
- DNS endpoint has no network allowlist. Master authorized networks do not apply to that name. It is reachable from any network that can reach Google APIs; the gate is IAM (`container.clusters.connect`). Kubernetes tokens and client certs on that name stay off. No VPC Service Controls on this trial account. The private IP endpoint stays limited to the app and infra subnet CIDRs
- HTTP-only Ingress (source-restricted LoadBalancer; no cert-manager in MVP)
- Manual GCE runner registration via IAP SSH
- No GitHub→GCP OIDC for Terraform yet (trust stays on GCE SA / ARC WI)
- ARC runner container `runAsUser: 0` for Kaniko (privilege reduction vs DinD, not a second security domain)
- Prod regional control-plane charge from create until delete; short screenshot window

## Non-goals

- Second GKE cluster for runners
- Custom `projectIamBinder` role; IAM Conditions on `container.admin` **instead of** a second project
- Narrowing `container.admin` / `cloudsql.admin` / `secretmanager.admin` **inside** a project
- App VPC in bootstrap; always-on dual stacks; three-zone prod
- Project-level `serviceAccountUser` on terraform-sa; bucket `storage.admin` (keep `objectAdmin`)
- IAM grants inside `bootstrap-env.sh`; prod SQL HA on `db-f1-micro`
- Perfect NetworkPolicy egress allow-lists; privileged DinD
- Full OIDC GitHub→GCP for Terraform; GitHub WIF / third IAM-only SA
- Automating GCE runner binary registration
- Renaming the existing project ID; org / folders / deny policies
- Moving WI into bootstrap; moving Cloud SQL PSA off env
- HPA / PDBs as required work
- Vault; Binary Authorization; service mesh
- External Secrets for anything other than the GitHub App secret. It syncs only `arc-github-app`. Database secrets are unchanged. The app still reads those through its own Workload Identity binding.

## Migration sketch

1. Prefer **destroy env then bootstrap** on the old shape (bootstrap that owns `module.app_network`) before applying slim bootstrap — greenfield network move, no `moved` across backends.
2. Per project: `setup_gcp` → `bootstrap-env.sh` (a successful apply disables `terraform-sa`) → register runner → env apply.
3. Re-register the GitHub runner with labels `self-hosted,infra,{env}` on `runner-vm-infra-{env}`.
4. Env apply: app VPC + peering → GKE (sizing from tfvars) → runner node pool + ARC SM shells, `arc-runners`, and External Secrets (`arc_install_charts = false`) → populate GitHub App secret versions → wait until ExternalSecret `arc-github-app` is Ready → `arc_install_charts = true` if needed. Rotation is a new Secret Manager version plus a listener restart; the listener reads the secret at pod start.
5. Prod: create project, fill prod tfvars → bring-up for screenshots → destroy **env the same day shots finish** → destroy bootstrap.
6. Full ops checklist: [docs/arc-cutover.md](../arc-cutover.md).

## References

**Official / vendor**

- [GitHub: Self-hosted runners — prefer ephemeral](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [GitHub: Actions Runner Controller concepts](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller)
- [GitHub: Deploying runner scale sets](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets)
- [GoogleCloudPlatform/arcgke](https://github.com/GoogleCloudPlatform/arcgke)
- [GCP Community: GKE runner sets + Workload Identity](https://medium.com/google-cloud/streamline-ci-cd-secure-gcp-deployments-with-gke-runner-sets-github-actions-workload-identity-fe851c6e2d60)

**Isolation / hardening**

- [AWS: Self-hosted runners at scale](https://aws.amazon.com/blogs/devops/best-practices-working-with-self-hosted-github-action-runners-at-scale-on-aws/)
- [Isolating GitHub Actions runners](https://blog.stephane-robert.info/en/docs/pipeline-cicd/github/runners/isolation/)
- [SEAL: Sandboxing & Isolation](https://frameworks.securityalliance.org/devsecops/isolation/sandboxing-and-isolation/)
- [Self-hosted runner hardening](https://www.systemshardening.com/articles/cicd/self-hosted-runner-hardening/)
- [ARC security: ephemeral + pod isolation](https://www.systemshardening.com/articles/cicd/actions-runner-controller-security/)
