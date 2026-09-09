# S3 — Incident Root Cause Investigation (AKS + ServiceNow)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `alert-response-incident-operations`

---

## Quick Start

Deploy the Terraform environment and register the S3 recipe:

Create the AKS incident in ServiceNow before running the simulation. The
workflow deliberately updates the existing incident instead of creating one.

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
triage, incident summary, and ServiceNow communications.

---

## Key Concepts

| Component | Role |
|-----------|------|
| **AKS Cluster** | Runs orders-api microservice workload |
| **Log Analytics** | Stores pod logs, node metrics, and events (`KubePodInventory`, `ContainerLogV2`, `KubeEvents`) |
| **Application Insights** | Captures application traces and errors |
| **Azure Monitor Alert** | Triggers on pod crash loop or node pressure |
| **ServiceNow Incident** | Owns incident lifecycle; agent updates with investigation notes |
| **Azure SRE Agent** | Coordinates the three incident-investigation subagents |

---

## How It Works

1. **Deploy broken workload** → pod enters CrashLoopBackOff immediately
2. **Azure Monitor alerts** (2–5 min) → detects pod crash via Log Analytics
3. **Incident matched** → An existing ServiceNow AKS incident matches the response plan
4. **Azure SRE Agent investigates** → Uses a three-subagent handoff chain
   - Examines `KubePodInventory` for pod state and restart counts
   - Checks `ContainerLogV2` for crash logs and error messages
   - Queries `InsightsMetrics` for resource pressure (CPU, memory)
   - Correlates recent deployment and configuration changes
   - Drafts the incident summary and ServiceNow work notes
5. **Updates ServiceNow** → The final agent updates only the active incident

---

## Architecture

<img src="../../images/s3-aks-infrastructure.svg" alt="S3 AKS infrastructure diagram" width="700" />

### Three-agent structure

The `alert-response-incident-operations` recipe follows the roles from
`leestott/On-Call-Copilot-Multi-Agent` without a separate hosted application.
Terraform creates the Azure SRE Agent, and the recipe registers this native
handoff chain:

```text
AKS triage -> summary -> ServiceNow communications -> main agent
```

Lee runs four roles concurrently. S3 combines Lee's summary and communication
outputs into a three-agent Azure SRE Agent handoff chain.

---

## Validation Checklist

After the quick start:
- Three S3 subagents are registered
- The AKS triage agent can query monitoring evidence
- The handoff chain completes in triage → summary → ServiceNow update order
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
