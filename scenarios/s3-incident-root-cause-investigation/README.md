# S3 — Incident Root Cause Investigation (AKS + ServiceNow)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `servicenow-aks-incident`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup

Set these values in `infra/terraform/environments/demo.tfvars`:

```hcl
scenario                     = "s3"
access_level                 = "High"
action_mode                  = "Review"
enable_service_now_connector = true
service_now_instance         = "https://<instance>.service-now.com"
service_now_username         = "<integration-user>"
```

Add `SERVICENOW_PASSWORD` to the GitHub Actions repository secrets. The workflow
passes it to Terraform and the incident-injection helper without storing it in
source control.

### Deploy & Observe

```bash
gh workflow run deploy.yml \
  -f environment=demo \
  -f plan=true \
  -f apply=true \
  -f simulate_aks_incident=true

gh run watch
```

The workflow deploys AKS, registers the S3 catalog, applies the broken workload,
and creates the ServiceNow incident that starts the investigation.

---

## Story

A new deployment hits AKS and the `orders-api` workload becomes unhealthy. Pods crash loop, nodes show pressure, or readiness probes fail. Azure Monitor detects the AKS symptoms, ServiceNow owns the incident lifecycle, and the Azure SRE Agent investigates via KQL queries, then safely restarts pods, drains nodes if needed, or rolls back the deployment. The incident record includes timeline, evidence, and all actions taken.

---

## Key Concepts

| Component | Role |
|-----------|------|
| **AKS Cluster** | Runs orders-api microservice workload |
| **Log Analytics** | Stores pod logs, node metrics, and events (`KubePodInventory`, `ContainerLogV2`, `KubeEvents`) |
| **Application Insights** | Captures application traces and errors |
| **Azure Monitor Alert** | Triggers on pod crash loop or node pressure |
| **ServiceNow Incident** | Owns incident lifecycle; agent updates with investigation notes |
| **SRE Agent** | Detects alert → queries logs → proposes remediation → executes fix |

---

## How It Works

1. **Deploy broken workload** → pod enters CrashLoopBackOff immediately
2. **Azure Monitor alerts** (2–5 min) → detects pod crash via Log Analytics
3. **ServiceNow incident created** → Alert triggers automation to open ticket
4. **SRE Agent investigates** → Runs KQL queries to find root cause
   - Examines `KubePodInventory` for pod state and restart counts
   - Checks `ContainerLogV2` for crash logs and error messages
   - Queries `InsightsMetrics` for resource pressure (CPU, memory)
5. **Proposes remediation** → Restart pod, drain node, or rollback deployment
6. **Approves & executes** → Human reviews (or auto-executes if `action_mode=Automatic`)
7. **Resolves incident** → Updates ServiceNow with timeline and evidence

---

## Architecture

<img src="../../images/s3-aks-infrastructure.svg" alt="S3 AKS infrastructure diagram" width="700" />

---

## Validation Checklist

After the quick start:
- ✅ Pod enters CrashLoopBackOff (`kubectl get pods -n default`)
- ✅ Azure Monitor alert fires (check Alerts page in portal)
- ✅ ServiceNow incident created with agent investigation notes
- ✅ Error rate correlates with pod restart events
- ✅ Incident resolves when pod recovers
- ✅ ServiceNow incident closed with timeline and evidence links

---

## Files & Locations

| What | Where |
|------|-------|
| S3 Terraform environment | `infra/terraform/environments/demo.tfvars` |
| Healthy workload | `infra/k8s/orders-api.yaml` |
| Broken workload (for demo) | `infra/k8s/orders-api-broken.yaml` |
| SRE Agent recipe | `recipes/servicenow-aks-incident/` |
| Alert rules | `infra/terraform/alerts.tf` |
| AKS configuration | `infra/terraform/aks.tf` |
| Knowledge base docs | `knowledge-base/` (runbooks, incident templates) |

---

## Next Steps

**After S3:**
- Advance to [S4 — Alert Response & Incident Operations](../s4-alert-response-incident-operations/README.md)
- Explore [S5 — PIM Elevation Audit](../s5-pim-elevation-audit/README.md) for compliance scenarios
- Try [S6 — Front Door Incident Response](../s6-frontdoor-incident-response/README.md) for CDN-level incidents

