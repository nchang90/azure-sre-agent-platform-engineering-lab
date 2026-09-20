# S3 — Incident Root Cause Investigation (AKS + Service Now)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `alert-response-incident-operations`

---

## Quick Start

Deploy the Terraform environment and register the S3 recipe:

The workflow deploys the healthy `checkout-api` workload to AKS:

```bash
gh workflow run deploy.yml \
  -f environment=demo \
  -f plan=true \
  -f apply=true

gh run watch
```

Once it completes, create or update the production incident and use the
Scenario A selector-drift variant as the failure being investigated.

### Scenario A — Ready pods, broken service routing

Apply the selector-drift manifest:

```bash
az aks get-credentials --resource-group rg-sre-lab-demo --name <aks-name> --admin
kubectl apply -f infra/k8s/checkout-api-service-no-endpoints.yaml
kubectl get service checkout-api --namespace default -o yaml
kubectl get endpoints checkout-api --namespace default
```

Expected effect:
- `checkout-api` pods stay `Running` and `Ready`
- CPU and memory stay near baseline
- the `checkout-api` `Service` keeps existing, but selects no endpoints
- callers start timing out or returning 5xx even though the pods do not look broken

This scenario keeps a single primary root-cause angle and a fixed evidence
trail for the agent to follow.

Terraform creates the Azure SRE Agent. The deployment workflow then registers
the three S3 subagents from the recipe.

---

## Production-style incident trigger

Use the scenario as a customer-impacting production outage rather than a simple
AKS failure drill. The strongest demo flow is:

```text
Production incident -> ServiceNow -> HTTP trigger -> Azure SRE Agent -> AKS triage -> root cause -> ServiceNow update
```

Create the incident in ServiceNow first, then let the workflow call the Azure
SRE Agent HTTP trigger with the incident context:

- **Alert:** `Checkout API availability has dropped below 99%`
- **Customer impact:** checkout requests intermittently fail or time out
- **Recent change:** a new `checkout-api` deployment was rolled out shortly before
  the alert
- **Initial signals:** pods are still `Running` and `Ready`; node CPU and memory
  look normal; no obvious crash-loop exists

If you want to show the alert handoff path, set
`webhook_bridge_trigger_url` so Azure Monitor or a ServiceNow workflow can post
directly into the agent HTTP trigger endpoint.

This keeps the scenario aligned to a realistic production flow: alert first,
customer impact second, ServiceNow incident creation third, evidence-led triage
fourth, and reporting back to the incident record without remediation.

---

## Story

A new deployment hits AKS and the `checkout-api` workload regresses in a way that
looks healthy from the pod view but breaks live traffic. The Azure SRE Agent
uses three focused subagents based on Lee's structure: AKS triage, incident
summary, and operator communications.

- **Scenario A root-cause angle:** the deployment introduces Kubernetes service
  selector drift, so traffic no longer reaches healthy pods.

The evidence path is deterministic: the same telemetry sources always produce
the same breadcrumb trail for the failure mode.

---

## Key Concepts

| Component | Role |
|-----------|------|
| **AKS Cluster** | Runs checkout-api microservice workload |
| **Log Analytics** | Stores pod logs, node metrics, and events (`KubePodInventory`, `ContainerLogV2`, `KubeEvents`) |
| **Application Insights** | Captures application traces and errors |
| **Azure Monitor Connector** | Supplies AKS and telemetry evidence to the Azure SRE Agent |
| **Azure Monitor Alert** | Provides the production signal for missing endpoints, workload loss, or node pressure |
| **ServiceNow Incident** | Acts as the system of record for the customer-facing outage |
| **HTTP Trigger** | Starts the Azure SRE Agent investigation from the ServiceNow workflow payload |
| **Azure SRE Agent** | Coordinates the three incident-investigation subagents |

---

## How It Works

1. **Deploy the broken service variant** → selector drift is introduced
2. **Azure Monitor alerts** (2–5 min) → detects service-without-endpoints or related AKS failure signals via Log Analytics
3. **ServiceNow incident created or updated** → the operator opens the production incident for the outage
4. **ServiceNow workflow calls the HTTP trigger** → incident metadata is sent to the Azure SRE Agent
5. **Azure SRE Agent investigates** → Uses a three-subagent handoff chain
   - Examines `KubePodInventory` for pod state and restart counts
   - Checks `KubeServices` / endpoints for selector drift
   - Checks `KubeEvents` for recent apply or service-related evidence
   - Checks `ContainerLogV2` only to confirm the app itself is not crashing
   - Correlates the failure with the most recent rollout or change window
   - Queries `InsightsMetrics` for resource pressure (CPU, memory)
   - Drafts the incident summary and ServiceNow-ready operator update
6. **Writes back the result** → `incident-comms-agent` posts the evidence-backed
   diagnosis onto the originating incident as a work note and attaches the RCA,
   using the `UpdateServiceNowIncident` and `UploadServiceNowAttachment` tools.
   Remediation stays manual.

### ServiceNow write-back

The write-back is governed by the `servicenow-incident-update` skill, which is the
single owner of ServiceNow write operations. The two tools are deliberately
narrow: `UpdateServiceNowIncident` writes `work_notes` (and `comments` only when
asked) and never touches state, assignment or close fields, so an agent update
can never resolve an incident.

Credentials come from `SERVICENOW_URL` / `SERVICENOW_USER` / `SERVICENOW_PASS` —
see [`.servicenow.env.sample`](../../.servicenow.env.sample). The PythonTool
sandbox cannot read environment variables, so `scripts/apply-extras.sh`
substitutes them into the tool body at apply time; use a dedicated integration
user scoped to the incident table.

If those variables are unset, the tools **and** the skill are skipped with a
warning and the rest of the catalog still applies — S3 then behaves as it did
before, composing the update for a human to post.

### Deterministic evidence paths

1. `KubePodInventory` still shows healthy `checkout-api` pods
2. `KubeServices` still shows the `checkout-api` `Service`
3. `kubectl get endpoints checkout-api -n default` returns no endpoints
4. Azure Monitor fires `AKS checkout-api service has no endpoints`
5. The agent concludes the failure is routing/configuration drift, not a broken pod

### Expected investigation output

For the demo to feel production-like, the final incident update should say:

- what customers saw: elevated checkout failures or timeouts
- what stayed healthy: AKS nodes and `checkout-api` pods
- what actually broke: the `checkout-api` `Service` selector no longer matched the
  healthy pods, leaving zero endpoints
- which resources were affected: the `checkout-api` deployment and `checkout-api`
  service in the `default` namespace
- which change is implicated: the most recent rollout that introduced selector
  drift
- what to do next: restore the healthy service selector or reapply the healthy
  manifest after operator approval

This gives the triage, summary, and communications subagents a realistic
production incident narrative to follow.

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
- A Sev1 AKS alert still provides the investigation signal and evidence trail
- Critical `checkout-api` workload or service deletion also raises a Sev1 AKS alert
- The ServiceNow workflow can call the Azure SRE Agent HTTP trigger with incident context
- Scenario A keeps pods healthy while reproducing broken routing with no endpoints
- The handoff chain completes in triage → summary → ServiceNow-ready report order
- The `rca-analysis` and `evidence-before-after` skills are registered for `scenario=s3`
- With ServiceNow credentials set, both write-back tools register and the work note lands on the incident
- Without them, the tools and `servicenow-incident-update` are skipped and the rest still applies
- The final update renders a numbered 5-Whys ladder and a Service-endpoint state delta
- No PIR or remediation subagent is added

---

## Files & Locations

| What | Where |
|------|-------|
| S3 Terraform environment | `infra/terraform/environments/demo.tfvars` |
| Healthy workload | `infra/k8s/checkout-api.yaml` |
| Scenario manifest | `infra/k8s/checkout-api-service-no-endpoints.yaml` |
| Legacy crash-loop demo manifest | `infra/k8s/checkout-api-broken.yaml` |
| Azure SRE Agent recipe | `recipes/alert-response-incident-operations/` |
| Alert rules | `infra/terraform/alerts.tf` |
| AKS configuration | `infra/terraform/aks.tf` |
| Knowledge base docs | `knowledge-base/` (runbooks, incident templates) |
| RCA narrative skill | `.github/skills/rca-analysis/SKILL.md` |
| ServiceNow write-back skill | `.github/skills/servicenow-incident-update/SKILL.md` |
| ServiceNow tools | `recipes/alert-response-incident-operations/config/tools/` |
| Before/after evidence skill | `.github/skills/evidence-before-after/SKILL.md` |
| S3 AKS runbooks | `knowledge-base/aks-*.md` |

---

## Next Steps

**After S3:**
- Advance to [S4 — Alert Response & Incident Operations](../s4-alert-response-incident-operations/README.md)
- Explore [S5 — PIM Elevation Audit](../s5-pim-elevation-audit/README.md) for compliance scenarios
- Try [S6 — Front Door Incident Response](../s6-frontdoor-incident-response/README.md) for CDN-level incidents
