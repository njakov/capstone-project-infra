# ADR 001: Runner isolation (infra GCE + in-cluster ARC)

**Status:** Accepted  
**Date:** 2026-09-20  
**Repo:** `capstone-project-infra`

## Context

Previously a single GCE VM lived in the **app VPC** and ran both Terraform (infra apply) and application CI/CD (Docker build, Helm deploy). That colocates a powerful Terraform identity with app build/deploy, widens blast radius, and makes it hard to teach least-privilege runner design.

This capstone must showcase private networking and runner isolation without the cost of a second GKE cluster or separate GCP projects.

## Decision

| Concern | Choice |
|---------|--------|
| Infra plane | **Per-env infra VPC + GCE runner** (`runner-vm-infra-{env}`), registered with labels `self-hosted`, `infra`, `{env}` |
| App CI plane | **ARC ephemeral runner scale sets** in the **same** env GKE cluster (`modules/arc`, scale set `petclinic-arc-{env}`) |
| Cluster topology | Same GKE as the app — **privilege reduction**, not a second security domain |
| In-cluster isolation | Dedicated namespaces (`arc-systems` / `arc-runners`), tainted `runners` node pool, demo-quality NetworkPolicies, Workload Identity |
| Build strategy on ARC | **Kaniko** (non-privileged); no DinD in MVP |
| Infra CI path | Single apply path: [`infra-pipeline.yml`](../../.github/workflows/infra-pipeline.yml) on infra-labeled runners |

### CIDR plan (same GCP project — must not collide)

| Network | Dev | Prod |
|---------|-----|------|
| App subnet | `10.10.0.0/24` | `10.11.0.0/24` |
| Pods / services | `10.20.0.0/16` / `10.30.0.0/16` | `10.21.0.0/16` / `10.31.0.0/16` |
| GKE master | `172.16.0.0/28` | `172.16.0.16/28` |
| Infra subnet | `10.50.0.0/24` | `10.51.0.0/24` |

Infra ↔ app VPC peering exports/imports **custom routes** so GCE infra runners can reach the private GKE control plane. GKE `master_authorized_networks_config` includes both the app subnet and the infra subnet CIDRs.

### IAM split

| Identity | Purpose | Notable roles |
|----------|---------|---------------|
| `github-infra-runner-sa-{env}` (GCE) | Terraform apply | Includes `projectIamAdmin` (**powerful-by-design** for module simplicity) + state bucket admin, network, GKE, Secret Manager admin |
| `github-app-runner-sa-{env}` (WI → ARC) | App build/deploy only | `artifactregistry.writer`, `container.developer` — **no** `projectIamAdmin`, **no** state admin, **no** `networkAdmin`, **no** `secretmanager.admin` |

## Consequences

- Bootstrap creates **two** VPCs + peering + an infra-only runner; first infra runner still needs a **local** bootstrap (chicken-egg).
- Infra workflows must use `runs-on: [self-hosted, infra, {env}]`.
- App workflows use ARC scale set names (`petclinic-arc-dev` / `petclinic-arc-prod`) and build images with **Kaniko** (no DinD).
- ARC runner pods run as UID 0 so the Kaniko executor can unpack layers under `/kaniko` (still no privileged Docker socket).
- Compromised ARC with deploy rights can still change Deployments **in that cluster**; this is accepted for the demo.
- Docker on the GCE infra VM uses the `docker` group (`runner` user) — never world-writable socket (`chmod 666`).
- App CI trusts GKE Workload Identity on ARC pods (not GitHub→GCP OIDC / `id-token`).

## Accepted risks (explicit)

- Same GCP project for `dev` and `prod`
- Same GKE cluster for app workloads and ARC runners
- Powerful infra SA (`projectIamAdmin`)
- HTTP-only Ingress (source-restricted LoadBalancer; no cert-manager in MVP)
- Manual GCE runner registration via IAP SSH
- No GitHub→GCP OIDC for Terraform yet (trust stays on GCE SA / ARC WI)
- ARC runner container `runAsUser: 0` for Kaniko (privilege reduction vs DinD, not a second security domain)

## Non-goals

- Second GKE cluster for runners; separate GCP projects
- Perfect NetworkPolicy egress allow-lists; privileged DinD
- Full OIDC GitHub→GCP for Terraform
- Automating GCE runner binary registration
- Vault / External Secrets; Binary Authorization; service mesh

## Migration sketch

1. Prefer **destroy/recreate bootstrap** for `dev` if state refactor is painful.
2. For `prod`, use Terraform `moved` blocks where possible after `dev` proves the shape (bootstrap already moves `module.network` → `module.app_network`).
3. Re-register the GitHub runner with labels `self-hosted,infra,{env}` on `runner-vm-infra-{env}`.
4. Env apply: runner node pool + ARC SM shells (`arc_install_charts = false`) → populate GitHub App secret versions → `arc_install_charts = true`.
5. Keep any old app-capable GCE registration until ARC Gate E is green, then decommission `runner-vm-{env}`.
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
- [Self-hosted runner hardening](https://www.systemshardening.com/articles/cicd/github-actions-self-hosted-runner/)
- [ARC security: ephemeral + pod isolation](https://www.systemshardening.com/articles/cicd/actions-runner-controller-security/)
