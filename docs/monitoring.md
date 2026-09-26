# Monitoring (PetClinic scrape path)

One working Prometheus → Grafana → alert path for the diploma demo. Not a full observability platform.

## Architecture

```text
PetClinic pod :8080
    └── Service http-web (ClusterIP, port 80 → 8080)
            └── ServiceMonitor (release=prometheus-community)
                    path: /actuator/prometheus
                    jobLabel: app.kubernetes.io/name  →  job="petclinic"
                            └── Prometheus (monitoring ns)
                                    ├── Grafana dashboard (sidecar, searchNamespace=ALL)
                                    └── PrometheusRule PetclinicInstanceDown
                                            └── Alertmanager UI (demo; no external webhook in MVP)
```

**Primary metrics path:** Spring Actuator Micrometer at `/actuator/prometheus` on the app Service port (`http-web` → container `8080`).

**Non-primary:** the image still attaches the Prometheus JMX Java agent on container port `9093` for optional local/debug use. That port is **not** on the Kubernetes Service and is **not** scraped by the cluster ServiceMonitor.

## What each repo owns

| Piece | Repo | Location |
|-------|------|----------|
| kube-prometheus-stack Helm values (retention, PVC, Grafana sidecar, selectors) | infra | [`modules/middleware`](../modules/middleware/) |
| ServiceMonitor, PrometheusRule, dashboard ConfigMap | app | [`chart/petclinic/templates`](https://github.com/njakov/capstone-project-app/tree/main/chart/petclinic/templates) |
| Actuator exposure (`health,info,prometheus`) | app | `application.properties` |

## Middleware defaults

Set in [`modules/middleware`](../modules/middleware/):

| Setting | Default | Notes |
|---------|---------|-------|
| `prometheus_retention` | `7d` | Enough for demos; override per env if needed |
| `prometheus_storage_size` | `10Gi` | RWO PVC for Prometheus |
| Grafana sidecar `searchNamespace` | `ALL` | Loads dashboard ConfigMaps from `petclinic` (and any other NS) |
| ServiceMonitor / rule namespace selectors | all namespaces | Picks up `release: prometheus-community` CRs from the app chart |
| `grafana_admin_password` | `null` | Chart default `prom-operator` if unset. CI: Environment secret `GRAFANA_ADMIN_PASSWORD`. Local: `TF_VAR_grafana_admin_password`. |

### Grafana admin credentials

Grafana’s admin password comes from the GitHub Environment secret `GRAFANA_ADMIN_PASSWORD` (exported as `TF_VAR_grafana_admin_password` when non-empty) or, for a local apply, from `TF_VAR_grafana_admin_password`. An empty secret must not override Terraform’s `null` default.

- **Do not** leave the chart default unmentioned: if `grafana_admin_password` is unset, Grafana admin is `admin` / `prom-operator` (kube-prometheus-stack default).
- Prod **apply** requires the Environment secret. Dev may omit it.
- For a local demo, set a one-time password without committing it:

```bash
# Local apply — Environment secret in CI, TF_VAR_ on a laptop
export TF_VAR_grafana_admin_password="$(gcloud secrets versions access latest --secret=grafana-admin-dev)"
```

Do not commit the value. Rotate after the defense if the default was used.

Port-forward Grafana:

```bash
kubectl -n monitoring port-forward svc/prometheus-community-grafana 3000:80
# open http://localhost:3000
```

## App chart resources

Deployed into the **`petclinic`** namespace with the app release:

1. **ServiceMonitor** — scrapes `http-web` → `/actuator/prometheus` every 15s; `jobLabel: app.kubernetes.io/name` so Prometheus `job` is `petclinic`.
2. **PrometheusRule** — `PetclinicInstanceDown` (`up{job="petclinic"} == 0` for 1m) plus CPU/heap warnings keyed on Micrometer tag `application="petclinic"`.
3. **Dashboard ConfigMap** — label `grafana_dashboard: "1"`; Micrometer JVM/HTTP dashboard (`4701_rev10.json`).

## Demo / Gate H checklist

1. **Scrape:** Prometheus → Status → Targets → `petclinic` /actuator path **UP**.
2. **Grafana:** PetClinic / Micrometer dashboard shows non-empty JVM and HTTP panels (select `application=petclinic`).
3. **Alert:** scale the Deployment to `0` (or break the Service) → after ~1m `PetclinicInstanceDown` fires in Prometheus Alerts / Alertmanager UI.

External Alertmanager sinks (Slack/email webhook) are **out of MVP**; firing in the UI is the accepted demo.

## Related docs

- [ADR 001: Runner isolation](adr/001-runner-isolation.md) — accepted risks; monitoring is orthogonal to runner trust.
- [README: Retarget GCP project](../README.md#retarget-gcp-project) — update tfvars and GitHub Environment `ALLOWED_SOURCE_RANGES` / `GRAFANA_ADMIN_PASSWORD` when switching projects.
- App README — Actuator / Helm deploy notes.
