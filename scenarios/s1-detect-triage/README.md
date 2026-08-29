# S1 — Incident Detection & Triage

**Persona:** Platform Engineering / On-call  
**Time:** ~15 minutes  
**Entry point:** Start here (foundation for S2–S6)  
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup
```bash
# 1. Copy and customize terraform.tfvars
cp recipes/azmon-lawappinsights/terraform/terraform.tfvars.example \
   infra/terraform/terraform.tfvars

# 2. Edit terraform.tfvars with your values:
# - resource_group_name = "s1-demo-rg"
# - location = "uksouth" (or your region)
# - agent_name = "s1-agent"
# - action_mode = "Review" (use "Automatic" after testing)
```

### Deploy & Observe (5 mins)
```bash
# Deploy infrastructure + SRE Agent
terraform -chdir=infra/terraform apply -auto-approve

# Register incident automations
bash scripts/apply-extras.sh s1

# Trigger incident: inject 5xx error spike
# Option A: Bad deployment
git checkout broken-feature-branch && git push

# Option B: Direct webhook trigger
curl -X POST https://<agent-endpoint>/trigger \
  -H "Content-Type: application/json" \
  -d '{"alert_type": "5xx_spike", "threshold": 50}'

# Watch it:
# - Azure Monitor alert fires (30–60 sec)
# - SRE Agent investigates via KQL
# - Root cause identified at file:line level
# - PR submitted automatically to fix
# - Incident resolved
```

---

---

## How It Works

1. **Alert fires** → Azure Monitor detects 5xx spike automatically
2. **Agent investigates** → Runs KQL queries against Log Analytics
3. **Root cause found** → Correlates spike with recent deployment/code change
4. **Fix proposed** → Submits PR with code correction
5. **Alert resolves** → Agent confirms incident is fixed

---

## How to Run

```bash
# Quickest way: use the break-app script
bash scripts/break-app.sh

# To restore:
APP_URL="$(cd infra/terraform && terraform output -raw orders_api_url)"
curl -X POST "$APP_URL/api/simulate/reset"
```

---

## Validation Checklist

After the quick start:
- ✅ Azure Monitor alert fires (check Alerts page in portal)
- ✅ SRE Agent investigates automatically
- ✅ PR appears in GitHub repo with fix proposal
- ✅ Error rate shown in Log Analytics
- ✅ Alert resolves when fix is applied
- ✅ Incident record saved for pattern matching

---

## Next: What Comes After S1

- **S2 — Autonomous Remediation**: Break the app at runtime (no code/infrastructure changes)
- **S3 — AKS Root Cause**: ServiceNow integration + Kubernetes incident investigation
- **S4 — Alert Response**: Operator-ready monitoring and incident creation workflows


az containerapp update -g <rg> -n orders-api --image <working-image>
```

---

## Step by Step

1. The `break-app.sh` script is no longer available (chaos monkey support has been removed).
2. A platform change introduces a regression in the production workload.
3. The `Orders API 5xx spike` Azure Monitor alert evaluates on a 5 minute window and typically appears within a few minutes.
4. The Incident Response Plan routes the alert to `orchestrator-agent`.
5. `orchestrator-agent` normalizes the alert into an `IncidentContext` (service, symptom, time window, environment) and classifies severity.
6. `orchestrator-agent` delegates to `triage-agent` for technical investigation.
7. `triage-agent` queries Log Analytics / Application Insights request data for the `5xx` spike and error patterns.
8. `triage-agent` queries Azure Monitor metrics — CPU, memory, latency, and deployment history — and correlates timing with the rogue revision or simulated change window.
9. If the app is reachable, `triage-agent` calls `GET /health` on orders-api and inspects `activeChangeRequest`.
10. `triage-agent` checks the available change record source and confirms whether there was an active CR.
11. `triage-agent` searches the knowledge base and matches the Unauthorized Change runbook.
12. `triage-agent` runs `az containerapp revision list` and identifies the rogue revision.
13. `triage-agent` searches the source repository and identifies the root cause at `file:line` level.
14. `orchestrator-agent` submits a fix PR with the proposed code change.
15. `orchestrator-agent` resolves the Azure Monitor alert and posts a structured incident summary.
16. Session insights are saved — the root cause, KQL queries, and fix pattern are stored for future incidents.

---

## Portal Steps

1. Open [sre.azure.com](https://sre.azure.com) and navigate to your agent.
2. Go to **Incidents** — a new incident thread should appear after the alert evaluation window completes, typically within ~5 to 10 minutes of running `break-app.sh`.
3. Open the incident thread and watch the agent work through steps 3–15 in real time.
4. Inspect the **Artifacts** panel: KQL query used, metrics snapshot, revision list output, and source file reference.
5. The final message shows the fix PR link, the resolved alert, and the saved session insight.

---

## Suggested Prompts

After the agent posts its findings, continue the thread to go deeper:

- *"Show me the KQL query you used to find the 5xx spike"*
- *"Which runbook matched and what were the key signals?"*
- *"What was the root cause at the source level?"*
- *"Why did you create a PR instead of deploying directly?"*
- *"What did you save for next time?"*

---

## Expected Output

After the alert window completes, the portal incident thread includes:

- The offending rogue revision name
- Evidence of missing CR (no active change record was found)
- The KQL error trace and Azure Monitor metrics correlation
- The root cause file and line number in the repository
- A submitted fix PR link
- The Azure Monitor alert marked as resolved
- A session insight entry for future incidents

---

## Validation

```bash
az containerapp revision list -n <orders-api-name> -g <rg> \
  -o table --query "[].{rev:name,active:properties.active,weight:properties.trafficWeight}"

azd env get-value AGENT_PORTAL_URL
```

---

## Knowledge Base

- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
- [http-500-errors.md](../knowledge-base/http-500-errors.md)
- [orders-architecture.md](../knowledge-base/orders-architecture.md)
