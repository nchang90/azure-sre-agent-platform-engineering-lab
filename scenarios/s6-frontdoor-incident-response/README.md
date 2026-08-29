# S6: Front Door Incident Response

**Learning Goal:** Demonstrate end-to-end SRE agent automation: incident detection at Azure Front Door → diagnosis via App Insights → intelligent remediation with human approval.

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
