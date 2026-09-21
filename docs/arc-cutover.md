# ARC + infra runner cutover checklist

Operational runbook for Plan 1 Wave 3: runner node pool, ARC module, infra workflow labels, **dev then prod**.

Do **not** run `terraform apply` / bootstrap scripts without explicit confirmation in chat. Prefer GitHub `infra-pipeline` plan → apply with Environment protection.

Related: [ADR 001](adr/001-runner-isolation.md), Gate E in the three-implementation plan.

---

## Prerequisites (already in code)

- [x] Infra workflows use `runs-on: [self-hosted, infra, {env}]` ([infra-pipeline.yml](../.github/workflows/infra-pipeline.yml))
- [x] GKE module creates tainted `runners` pool (`github.runner=true:NoSchedule`, label `workload=github-runner`)
- [x] `modules/arc` + env wiring (`enable_arc`, `arc_install_charts`)
- [x] App-runner GCP SA + WI binding (`arc-runners` / `arc-runner`) in `modules/identity`
- [x] External Secrets syncs the GitHub App Secret Manager shells into `arc-github-app` (`modules/external-secrets`). Database secrets are unchanged.

---

## Dev cutover

### 1. Infra runner online

1. Bootstrap already applied (infra VPC + peering + `runner-vm-infra-dev`).
2. IAP SSH → register GitHub runner with labels **`self-hosted,infra,dev`**.
3. Verify: from the VM, `gcloud container clusters get-credentials --dns-endpoint` + `kubectl get nodes` (Gate C). Peering does not reach the private IP control plane; Terraform uses the DNS endpoint over Private Google Access.

### 2. Apply env stack — runner pool, Secret Manager shells, External Secrets, arc-runners

In `environments/dev/terraform.tfvars`:

```hcl
enable_arc         = true
arc_install_charts = false
```

Run **plan then apply** for `environments/dev` (infra pipeline or local from the infra runner).

Expect:

- Node pool `runners` on the GKE cluster
- Secret Manager secrets: `arc-github-app-id-dev`, `arc-github-app-installation-id-dev`, `arc-github-app-private-key-dev`
- Namespace `arc-runners`, plus the External Secrets operator in namespace `external-secrets`
- `ExternalSecret` `arc-github-app` in `arc-runners`. It is not Ready until the three secret versions exist. Terraform does not create Kubernetes secret `arc-github-app`.
- Terraform outputs `arc_github_app_secret_ids` and `arc_runner_scale_set_name` (`petclinic-arc-dev`)

### 3. Create a GitHub App (once per org/user)

1. GitHub → Settings → Developer settings → GitHub Apps → New.
2. Permissions (minimum): **Repository** → Actions (Read), Administration (Read), Metadata (Read); **Organization** if org-level runners as needed. For repo-level scale sets targeting `capstone-project-app`, grant access to that repository.
3. Generate a **private key** (download PEM).
4. Install the App on `njakov/capstone-project-app` (or the org) and note the **installation ID**.
5. Note the **App ID**.

### 4. Populate Secret Manager versions

```bash
PROJECT_ID="<your-gcp-project>"
ENV=dev

# App ID and installation ID are short strings
printf '%s' '<APP_ID>' | gcloud secrets versions add "arc-github-app-id-${ENV}" \
  --project="$PROJECT_ID" --data-file=-

printf '%s' '<INSTALLATION_ID>' | gcloud secrets versions add "arc-github-app-installation-id-${ENV}" \
  --project="$PROJECT_ID" --data-file=-

# Private key PEM file
gcloud secrets versions add "arc-github-app-private-key-${ENV}" \
  --project="$PROJECT_ID" --data-file=./github-app.pem
```

### 5. Wait until ExternalSecret `arc-github-app` is Ready

Run this on the **infra runner**, after the secret versions exist and **before** `arc_install_charts = true`. The shells apply already installed External Secrets and created `ExternalSecret` `arc-github-app` in `arc-runners`. That object copies `arc-github-app-id-${ENV}`, `arc-github-app-installation-id-${ENV}`, and `arc-github-app-private-key-${ENV}` into Kubernetes secret `arc-github-app` (`github_app_id`, `github_app_installation_id`, `github_app_private_key`).

Do not create that secret with `kubectl`, and do not import it into Terraform. A refresh of a Terraform-managed secret would write the PEM back into state. Helm still references the name `arc-github-app` in `arc-runners`. If an earlier apply owned the secret, the next plan forgets that object and leaves it in the cluster for the ExternalSecret (`creationPolicy: Owner`) to adopt.

```bash
PROJECT_ID="<your-gcp-project>"
ENV=dev
REGION=europe-west1
APP_NAME=petclinic

gcloud container clusters get-credentials "${APP_NAME}-gke-${ENV}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --dns-endpoint

kubectl get externalsecret arc-github-app -n arc-runners
```

Wait until that ExternalSecret is Ready (`STATUS` `SecretSynced`). Then confirm the synced secret:

```bash
kubectl get secret arc-github-app -n arc-runners
```

**Rotation:** add a new Secret Manager version, wait for the ExternalSecret to refresh (interval 1h), then restart the ARC listener. The listener reads `arc-github-app` at pod start.

Database secrets are unchanged. The app still reads those through its own Workload Identity binding.

### 6. Install ARC charts

Set in `environments/dev/terraform.tfvars`:

```hcl
arc_install_charts = true
```

Plan + apply again. Expect:

- Namespace `arc-systems` (`arc-runners` already exists, with secret `arc-github-app` synced by External Secrets)
- Helm releases: controller + scale set `petclinic-arc-dev`
- NetworkPolicies (default-deny + DNS/HTTPS egress)
- GitHub → Settings → Actions → Runners shows **`petclinic-arc-dev`**

### 7. Gate E verification (dev)

| Check | Command / UI |
|-------|----------------|
| Scale set online | GitHub Actions runners UI → `petclinic-arc-dev` |
| Scheduling | `kubectl get pods -n arc-runners -o wide` — nodes should be from the `runners` pool |
| NetworkPolicy smoke | From an ARC pod: HTTPS to GitHub/AR works; curl to PetClinic ClusterIP **fails** |
| Kaniko spike | App repo Plan 2 — PR/main workflows build with Kaniko on `petclinic-arc-{env}` |

**Rollback:** keep any old app-capable GCE runner registration until the first green ARC job; do not delete it in this step. App workflow `runs-on` flips belong to Plan 2.

---

## Prod cutover (only after Gate E green on dev)

Repeat the same sequence with `ENV=prod` / `runner-vm-infra-prod` / labels `self-hosted,infra,prod` / secrets `*-prod` / scale set `petclinic-arc-prod`.

Rules:

- Never skip DNS-endpoint access from the infra runner (Gate C) on prod.
- Do not set `arc_install_charts = true` on prod until the matching secret versions exist and `ExternalSecret` `arc-github-app` in `arc-runners` is Ready.
- Prefer `moved` / careful apply over destroy for prod bootstrap if already migrated.

---

## Decommission old colocated runners

After ARC is green on an environment **and** app workflows no longer use the old GCE labels:

1. Remove the old GitHub runner registration for `runner-vm-{env}` (if still present).
2. Destroy leftover VMs only if bootstrap no longer manages them (confirm state).
3. Regenerate [`.github/assets/architecture-diagram.png`](../.github/assets/architecture-diagram.png) to match infra VPC + ARC.

---

## Acceptance (Plan 1 Wave 3 done)

- Infra apply only on `[self-hosted, infra, {env}]`
- `petclinic-arc-dev` visible in GitHub (prod after its cutover)
- Runner pods schedule on the tainted pool
- Infra runner reaches the GKE control plane through the DNS endpoint (not peering custom routes)
- ADR + README describe ARC as installed (not “later phase”) once charts are live
