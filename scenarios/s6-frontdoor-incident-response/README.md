# S6: Front Door Incident Response

**Learning Goal:** Demonstrate end-to-end SRE agent automation: incident detection at Azure Front Door → diagnosis via App Insights → intelligent remediation with human approval.

---

## ⚡ Quick Start: 5-Minute Lab (Hands-on)

### Learning Objectives
By completing this lab, you'll:
- Understand CDN-level incident detection with Azure Front Door
- See how SRE Agent diagnoses 502/503 errors
- Learn to approve and execute automated remediation
- Understand failover and health probe workflows

### Prerequisites
- Azure subscription with Owner or Contributor role
- Terraform installed locally
- `az cli` authenticated
- Azure Monitor configured with action groups

### Exercise: Break It at the CDN Edge, Watch It Heal (5 mins)

**Step 1: Deploy S6 infrastructure** (1 min)
```bash
# Deploy Front Door + Container Apps with health probes
terraform -chdir=infra/terraform apply -auto-approve \
  -var-file=recipes/azmon-lawappinsights/terraform/terraform.tfvars.example \
  -var="resource_group_name=s6-demo-rg" \
  -var="scenario=s6"

# ✅ Check: Verify Front Door and Container Apps running
az container app list --resource-group s6-demo-rg
az resource show --resource-group s6-demo-rg --resource-type "Microsoft.Cdn/profiles" --name s6-frontdoor
```

**Step 2: Register SRE Agent automation** (1 min)
```bash
# Apply incident response plans and runbooks
bash scripts/apply-extras.sh s6

# ✅ Check: Verify agent can access Front Door metrics
az monitor action-group list --resource-group s6-demo-rg
```

**Step 3: Trigger incident at the edge** (1 min)
```bash
# Misconfigure Front Door routing rule to cause 502 Bad Gateway
# Option A: Break the health probe endpoint
kubectl patch deployment orders-api -n default \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"orders-api","env":[{"name":"HEALTH_ENDPOINT_DOWN","value":"true"}]}]}}}}'

# Option B: Scale down Container Apps replicas to simulate backend failure
az container app replica set list --resource-group s6-demo-rg --name orders-api
az container app scale --resource-group s6-demo-rg --name orders-api --target 0

# ✅ Check: Watch Azure Monitor alert fire
az monitor metrics list --resource-group s6-demo-rg --metric "BackendHealthPercentage" --timespan "PT5M"
```

**Step 4: SRE Agent proposes fix** (1 min)
```bash
# Agent investigates:
# - Front Door health probe failures
# - Application Insights for backend error patterns
# - Dependency traces to isolate root cause
# - Correlation with recent deployments

# Proposed remediation:
# - Scale up Container Apps replicas
# - Update Front Door backend pool to healthy backends
# - Drain unhealthy origins

# ✅ Check: Verify remediation proposal received
# Look for: Incident record with "Proposed Actions" section
# Expected actions: Scale replicas, drain unhealthy pool, or failover to backup
```

**Step 5: Approve and execute fix** (1 min)
```bash
# Review remediation proposal and approve execution
# (Or set action_mode=Automatic for full automation)

# Option A: Manual approval via CLI
az rest --method post \
  --url https://management.azure.com/subscriptions/<sub>/resourcegroups/s6-demo-rg/providers/Microsoft.App/agents/s6-agent/actions/approve?api-version=2025-05-01 \
  --body '{"incident_id": "<id>", "approval": true}'

# Option B: Automatic execution (if configured)
# Agent automatically scales Container Apps to 3 replicas
# and updates Front Door backend pool

# ✅ Validation: Confirm incident resolved
# - Front Door health probe passes (BackendHealthPercentage = 100)
# - Application Insights shows error rate dropping
# - Container Apps shows 3 replicas Running
# - Azure Monitor alert status: Resolved
```

### What You Learned
- CDN-level incident detection and routing
- Health probe configuration and failure handling
- Multi-layer diagnostics (Front Door + App Insights)
- Remediation workflows with human approval gates

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Azure Front Door (CDN/Edge)                            │
│  - Frontend Endpoint (broken-route.example.com)         │
│  - Routing Rule (misconfigured backend pool)            │
│  - Health Probes (checking /health)                     │
└────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Azure Container Apps                                   │
│  - Orders API (microservice)                            │
│  - Environment: 2 replicas                              │
│  - Health endpoint: /health                             │
└────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Application Insights + Log Analytics                   │
│  - Track HTTP 502/503 errors                            │
│  - Monitor origin health probe failures                 │
│  - Dependency call traces                               │
└────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Azure SRE Agent (Incident Response)                    │
│  1. Detector: Receives Azure Monitor alert (503 spike)  │
│  2. Triage: Queries logs → identifies Front Door issue  │
│  3. Investigation: Correlates with health probe fails   │
│  4. Remediation: Proposes fix (failover to healthy pool)│
│  5. Approval: Waits for human sign-off                  │
│  6. Execution: Scales up replicas, validates fix        │
└─────────────────────────────────────────────────────────┘
```

## Scenario Flow

### Phase 1: Setup (10 min)
- Deploy infrastructure (Front Door, Container Apps, App Insights)
- Create health probe alert rule in Azure Monitor
- Seed SRE agent with incident runbooks

### Phase 2: Incident Simulation (5 min)
- Simulate Front Door routing rule misconfiguration
- Health probes begin failing
- Azure Monitor fires alert (HTTP 503)

### Phase 3: SRE Agent Response (15 min)
- **Detector**: Ingests alert → creates incident record
- **Triage**: Queries logs → diagnoses root cause (health probe failure)
- **Investigation**: Correlates events → builds timeline
- **Remediation**: Proposes fix (scale replicas, check routing rule)
- **Approval**: Human reviews & approves action
- **Execution**: Applies fix → monitors for 5 min → resolves incident

### Phase 4: Validation (5 min)
- Confirm health probes passing
- Verify traffic through Front Door restored
- Post-incident review: document in knowledge-base/incident-report.md

## Key Skills & Runbooks Used

| Phase | Skill/Runbook |
|-------|---|
| Detection | investigate-azure-alerts |
| Triage | knowledge-base/runbooks/frontdoor/frontdoor-broken-routing.md |
| Investigation | KQL: Health probe failures, 503 error trends |
| Remediation | Azure CLI: scale container app, update routing rule |

## What You'll Learn

✅ How Azure Front Door health probes trigger incident detection  
✅ How SRE agents triage multi-layer incidents (edge → app → monitoring)  
✅ How approval gates protect against auto-remediation mistakes  
✅ How to correlate logs across Application Insights and Front Door metrics  
✅ Post-incident documentation workflow  

## Commands

```bash
# 1. Deploy S6 infrastructure
cd scenarios/s6-frontdoor-incident-response
./scripts/deploy.sh

# 2. Simulate incident
./scripts/simulate-incident.sh

# 3. Trigger SRE agent response
# (Agent auto-responds to Azure Monitor alert)

# 4. View incident progress
./scripts/watch-incident.sh

# 5. Review final report
cat knowledge-base/incident-report.md
```

## Expected Outcomes

| Expectation | Evidence |
|---|---|
| Alert fires within 2 min | Azure Monitor alert history |
| SRE agent detects within 5 min | Incident record in agent logs |
| Triage complete within 10 min | Root cause identified in runbook output |
| Fix approved & executed | Azure CLI audit trail, Container Apps replica count increased |
| Incident resolved within 20 min | Health probes passing, traffic restored, 503 errors drop to 0 |

## Files

- `README.md` (this file) — Scenario overview
- `scripts/deploy.sh` — Infrastructure deployment
- `scripts/simulate-incident.sh` — Trigger Front Door misconfiguration
- `scripts/watch-incident.sh` — Monitor SRE agent response
- `resources/frontdoor-routing-rule.bicep` — Front Door test configuration
- `resources/app-insights-alert-rule.bicep` — Azure Monitor alert for 503 spikes
