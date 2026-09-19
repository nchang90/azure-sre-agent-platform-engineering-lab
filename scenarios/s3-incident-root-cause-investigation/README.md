# S3 — Incident Root Cause Investigation (AKS + Azure Monitor)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `alert-response-incident-operations`

---

## Quick Start

Deploy the Terraform environment and register the S3 recipe:

The workflow deploys the healthy `orders-api` workload to AKS:

```bash
gh workflow run deploy.yml \
  -f environment=demo \
  -f plan=true \
  -f apply=true

gh run watch
```

Once it completes, choose one of the two deterministic incident variants below to
raise the incident.

### Scenario A — Ready pods, broken service routing

Apply the selector-drift manifest:

```bash
az aks get-credentials --resource-group rg-sre-lab-demo --name <aks-name> --admin
kubectl apply -f infra/k8s/orders-api-service-no-endpoints.yaml
kubectl get service orders-api --namespace default -o yaml
kubectl get endpoints orders-api --namespace default
```

Expected effect:
- `orders-api` pods stay `Running` and `Ready`
- CPU and memory stay near baseline
- the `orders-api` `Service` keeps existing, but selects no endpoints
- callers start timing out or returning 5xx even though the pods do not look broken

### Scenario B — Bad rollout image, pull fails

Apply the image-pull failure manifest:

```bash
az aks get-credentials --resource-group rg-sre-lab-demo --name <aks-name> --admin
kubectl apply -f infra/k8s/orders-api-imagepull.yaml
kubectl rollout status deployment/orders-api --namespace default --timeout=120s
```

Expected effect:
- the new rollout never becomes healthy
- pods show `ErrImagePull` / `ImagePullBackOff`
- Azure Monitor raises the Sev1 AKS unhealthy-workload incident automatically

Both variants map to the same S3 investigation flow, but each one has a single
primary root-cause angle and a fixed evidence trail for the agent to follow.

Terraform creates the Azure SRE Agent. The deployment workflow then registers
the three S3 subagents from the recipe.

---

## Story

A new deployment hits AKS and the `orders-api` workload regresses. The Azure
SRE Agent uses three focused subagents based on Lee's structure: AKS triage,
incident summary, and operator communications.

- **Scenario A root-cause angle:** the deployment introduces Kubernetes service
  selector drift, so traffic no longer reaches healthy pods.
- **Scenario B root-cause angle:** the deployment references an invalid image,
  so the new pods never start successfully.

The evidence path is deterministic in both cases: the same telemetry sources
always produce the same breadcrumb trail for the chosen failure mode.

---

## Key Concepts

| Component | Role |
|-----------|------|
| **AKS Cluster** | Runs orders-api microservice workload |
| **Log Analytics** | Stores pod logs, node metrics, and events (`KubePodInventory`, `ContainerLogV2`, `KubeEvents`) |
| **Application Insights** | Captures application traces and errors |
| **Azure Monitor Connector** | Feeds the S3 Log Analytics-scoped Azure Monitor incidents into the Azure SRE Agent |
| **Azure Monitor Alert** | Triggers on pod crash loop, critical workload loss, missing service, or node pressure |
| **Azure Monitor Incident** | Created from the Sev1 AKS alert and owns the investigation lifecycle |
| **ServiceNow Incident** | Existing active AKS incident receives the simulation context as a work note |
| **Azure SRE Agent** | Coordinates the three incident-investigation subagents |

---

## How It Works

1. **Deploy one broken variant** → either selector drift or image pull failure is introduced
2. **Azure Monitor alerts** (2–5 min) → detects service-without-endpoints, unhealthy workload, or related AKS failure signals via Log Analytics
3. **Incident created** → The Sev1 AKS alert matches the `aks-critical-errors` response plan
4. **Azure SRE Agent investigates** → Uses a three-subagent handoff chain
   - Examines `KubePodInventory` for pod state and restart counts
   - Checks `KubeServices` / endpoints for selector drift in Scenario A
   - Checks `KubeEvents` for `ErrImagePull` / `ImagePullBackOff` in Scenario B
   - Checks `ContainerLogV2` for crash or probe evidence when logs exist
   - Queries `InsightsMetrics` for resource pressure (CPU, memory)
   - Correlates recent deployment and configuration changes
   - Drafts the incident summary and operator update
5. **Updates incidents** → The agent returns an evidence-backed Azure Monitor update, while the workflow records the simulation in the existing ServiceNow incident

### Deterministic evidence paths

#### Scenario A — selector drift / no endpoints

1. `KubePodInventory` still shows healthy `orders-api` pods
2. `KubeServices` still shows the `orders-api` `Service`
3. `kubectl get endpoints orders-api -n default` returns no endpoints
4. Azure Monitor fires `AKS orders-api service has no endpoints`
5. The agent concludes the failure is routing/configuration drift, not a broken pod

#### Scenario B — invalid image reference

1. rollout starts immediately after the manifest apply
2. `KubeEvents` shows `Failed`, `ErrImagePull`, or `ImagePullBackOff`
3. `KubePodInventory` shows unhealthy or non-running pods
4. Azure Monitor fires `AKS orders-api workload unhealthy`
5. The agent concludes the failure is rollout/image regression, not load or node pressure

---

## Architecture

<img src="../../images/s3-aks-infrastructure.svg" alt="S3 AKS infrastructure diagram" width="700" />

### Three-agent structure

The `alert-response-incident-operations` recipe follows the roles from
`leestott/On-Call-Copilot-Multi-Agent` without a separate hosted application.
Terraform creates the Azure SRE Agent, and the recipe registers this native
handoff chain:

```text
AKS triage -> summary -> incident communications -> main agent
```

Lee runs four roles concurrently. S3 combines Lee's summary and communication
outputs into a three-agent Azure SRE Agent handoff chain.

---

## Validation Checklist

After the quick start:
- Three S3 subagents are registered
- The AKS triage agent can query monitoring evidence
- A Sev1 AKS alert creates an Azure Monitor incident automatically
- Critical `orders-api` workload or service deletion also raises a Sev1 AKS alert
- Scenario A keeps pods healthy while reproducing broken routing with no endpoints
- Scenario B reproduces an image-pull failure with AKS unhealthy-workload evidence
- The newest active matching ServiceNow incident receives an S3 work note
- The handoff chain completes in triage → summary → incident update order
- No PIR or remediation subagent is added

---

## Files & Locations

| What | Where |
|------|-------|
| S3 Terraform environment | `infra/terraform/environments/demo.tfvars` |
| Healthy workload | `infra/k8s/orders-api.yaml` |
| Scenario A manifest | `infra/k8s/orders-api-service-no-endpoints.yaml` |
| Scenario B manifest | `infra/k8s/orders-api-imagepull.yaml` |
| Legacy crash-loop demo manifest | `infra/k8s/orders-api-broken.yaml` |
| Azure SRE Agent recipe | `recipes/alert-response-incident-operations/` |
| Alert rules | `infra/terraform/alerts.tf` |
| AKS configuration | `infra/terraform/aks.tf` |
| Knowledge base docs | `knowledge-base/` (runbooks, incident templates) |
| S3 AKS runbooks | `knowledge-base/aks-*.md` |

---

## Next Steps

**After S3:**
- Advance to [S4 — Alert Response & Incident Operations](../s4-alert-response-incident-operations/README.md)
- Explore [S5 — PIM Elevation Audit](../s5-pim-elevation-audit/README.md) for compliance scenarios
- Try [S6 — Front Door Incident Response](../s6-frontdoor-incident-response/README.md) for CDN-level incidents
