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

---

## Dev cutover

### 1. Infra runner online

1. Bootstrap already applied (infra VPC + peering + `runner-vm-infra-dev`).
2. IAP SSH → register GitHub runner with labels **`self-hosted,infra,dev`**.
3. Verify: from the VM, `gcloud container clusters get-credentials` + `kubectl get nodes` against the **private** endpoint (Gate C).

### 2. Apply env stack — runner pool + Secret Manager shells

In `environments/dev/terraform.tfvars`:

```hcl
enable_arc         = true
arc_install_charts = false
```

Run **plan then apply** for `environments/dev` (infra pipeline or local from the infra runner).

Expect:

- Node pool `runners` on the GKE cluster
- Secret Manager secrets: `arc-github-app-id-dev`, `arc-github-app-installation-id-dev`, `arc-github-app-private-key-dev`
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

### 5. Install ARC charts

Set in `environments/dev/terraform.tfvars`:

```hcl
arc_install_charts = true
```

Plan + apply again. Expect:

- Namespaces `arc-systems`, `arc-runners`
- Helm releases: controller + scale set `petclinic-arc-dev`
- NetworkPolicies (default-deny + DNS/HTTPS egress)
- GitHub → Settings → Actions → Runners shows **`petclinic-arc-dev`**

### 6. Gate E verification (dev)

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

- Never skip private-API access from the infra runner (Gate C) on prod.
- Do not set `arc_install_charts = true` on prod until the matching secret versions exist.
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
- Peering still reaches private GKE API from infra GCE
- ADR + README describe ARC as installed (not “later phase”) once charts are live
