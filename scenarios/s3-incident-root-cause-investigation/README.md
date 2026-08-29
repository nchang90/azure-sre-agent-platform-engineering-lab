# S3 — Incident Root Cause Investigation (AKS + ServiceNow)

**Persona:** Platform SRE / Incident Commander  
**Time:** ~12 minutes  
**Recipe:** `servicenow-aks-incident`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup
```bash
# 1. Copy and customize the S3 terraform.tfvars
cp recipes/servicenow-aks-incident/terraform/terraform.tfvars.example \
   infra/terraform/terraform.tfvars

# 2. Edit terraform.tfvars with your values:
# - resource_group_name = "s3-demo-rg"
# - location = "uksouth" (or your region)
# - agent_name = "s3-agent"
# - enable_service_now_connector = true  (or false to skip ServiceNow)
# - service_now_instance_url = "https://<your-instance>.service-now.com"
# - service_now_username = "<your-username>"
# - action_mode = "Review" (use "Automatic" after testing)

# 3. Provide ServiceNow password via environment variable:
export TF_VAR_service_now_password="<your-password>"
```

### Deploy & Observe (5 mins)
```bash
# Deploy infrastructure
terraform -chdir=infra/terraform apply -auto-approve

# Register SRE Agent automations
bash scripts/apply-extras.sh s3

# Trigger incident: deploy broken workload
kubectl apply -f infra/k8s/orders-api-broken.yaml

# Watch it auto-respond:
# - Pod CrashLoopBackOff (immediate)
# - Azure Monitor alert fires (2–5 min)
# - ServiceNow incident created
# - SRE Agent investigates via KQL
# - Pod restarts/remediation applied
# - Incident resolved
```

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

## Terraform Configuration

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
| S3 terraform.tfvars example | `recipes/servicenow-aks-incident/terraform/terraform.tfvars.example` |
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


