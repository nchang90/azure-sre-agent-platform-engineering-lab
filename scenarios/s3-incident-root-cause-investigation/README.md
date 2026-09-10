# S3 — Incident Root Cause Investigation (AKS + Azure Monitor)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `alert-response-incident-operations`

---

## Quick Start

Deploy the Terraform environment and register the S3 recipe:

The workflow deploys a broken AKS workload. Its Sev1 Azure Monitor alert creates
an SRE Agent incident automatically, matching the S0/S1 incident flow. It also
adds the simulation context to the newest active ServiceNow incident whose short
description contains `AKS`.

Before running the workflow, create that active ServiceNow incident and set the
repository secret `SERVICENOW_PASSWORD`. The demo environment supplies the
ServiceNow instance URL and username.

```bash
gh workflow run deploy.yml \
  -f environment=demo \
  -f plan=true \
  -f apply=true \
  -f simulate_aks_incident=true

gh run watch
```

Terraform creates the Azure SRE Agent. The deployment workflow then registers
the three S3 subagents from the recipe.

---

## Story

A new deployment hits AKS and the `orders-api` workload becomes unhealthy. The
Azure SRE Agent uses three focused subagents based on Lee's structure: AKS
triage, incident summary, and operator communications.

---

## Key Concepts

| Component | Role |
|-----------|------|
| **AKS Cluster** | Runs orders-api microservice workload |
| **Log Analytics** | Stores pod logs, node metrics, and events (`KubePodInventory`, `ContainerLogV2`, `KubeEvents`) |
| **Application Insights** | Captures application traces and errors |
| **Azure Monitor Alert** | Triggers on pod crash loop or node pressure |
| **Azure Monitor Incident** | Created from the Sev1 AKS alert and owns the investigation lifecycle |
| **ServiceNow Incident** | Existing active AKS incident receives the simulation context as a work note |
| **Azure SRE Agent** | Coordinates the three incident-investigation subagents |

---

## How It Works

1. **Deploy broken workload** → pod enters CrashLoopBackOff immediately
2. **Azure Monitor alerts** (2–5 min) → detects pod crash via Log Analytics
3. **Incident created** → The Sev1 AKS alert matches the `aks-critical-errors` response plan
4. **Azure SRE Agent investigates** → Uses a three-subagent handoff chain
   - Examines `KubePodInventory` for pod state and restart counts
   - Checks `ContainerLogV2` for crash logs and error messages
   - Queries `InsightsMetrics` for resource pressure (CPU, memory)
   - Correlates recent deployment and configuration changes
   - Drafts the incident summary and operator update
5. **Updates incidents** → The agent returns an evidence-backed Azure Monitor update, while the workflow records the simulation in the existing ServiceNow incident

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
- The newest active matching ServiceNow incident receives an S3 work note
- The handoff chain completes in triage → summary → incident update order
- No PIR or remediation subagent is added

---

## Files & Locations

| What | Where |
|------|-------|
| S3 Terraform environment | `infra/terraform/environments/demo.tfvars` |
| Healthy workload | `infra/k8s/orders-api.yaml` |
| Broken workload (for demo) | `infra/k8s/orders-api-broken.yaml` |
| Azure SRE Agent recipe | `recipes/alert-response-incident-operations/` |
| Alert rules | `infra/terraform/alerts.tf` |
| AKS configuration | `infra/terraform/aks.tf` |
| Knowledge base docs | `knowledge-base/` (runbooks, incident templates) |

---

## Next Steps

**After S3:**
- Advance to [S4 — Alert Response & Incident Operations](../s4-alert-response-incident-operations/README.md)
- Explore [S5 — PIM Elevation Audit](../s5-pim-elevation-audit/README.md) for compliance scenarios
- Try [S6 — Front Door Incident Response](../s6-frontdoor-incident-response/README.md) for CDN-level incidents
