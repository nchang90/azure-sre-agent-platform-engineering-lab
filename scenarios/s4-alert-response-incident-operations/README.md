# S4 — Alert Response and Incident Operations

**Persona:** Platform Operations / On-call SRE  
**Time:** ~10 minutes (after S1)  
**Prerequisite:** S1 infrastructure deployed  
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup
```bash
# S1 infrastructure must be running
# Verify Azure Monitor alerts are configured
az monitor metrics-alert list --resource-group s1-demo-rg
# Expected: At least one alert for orders-api availability ✅
```

### Deploy & Observe (5 mins)
```bash
# Register S4 incident response automation
bash scripts/apply-extras.sh s4

# Trigger availability failure
APP_URL="$(cd infra/terraform && terraform output -raw orders_api_url)"
curl -X POST "$APP_URL/api/simulate/failure-rate/100"

# Alert fires → SRE Agent investigates automatically:
# - Queries Application Insights for failed requests
# - Traces dependency failures
# - Correlates with metrics and traces
# - Generates incident summary with owner, severity, timeline, evidence

# Watch the incident summary appear in portal
# Should include: impact, affected service, failed endpoints, error types, recovery status

# Restore service
curl -X POST "$APP_URL/api/simulate/reset"
```

---

## Story

Operator receives an availability alert for the orders-api service. The SRE Agent automatically gathers evidence—failed requests, exceptions, traces, dependencies—and produces a short, evidence-backed incident summary with severity, timeline, owner, and next action. Operator can now confidently escalate or close the loop with exact telemetry.

---

## How It Works

1. **Alert fires** → Azure Monitor detects availability failure
2. **Agent investigates** → Queries Application Insights for requests, exceptions, traces, dependencies
3. **Correlates** → Matches failure window with telemetry patterns
4. **Summarizes** → Produces incident summary with impact, timeline, suspected cause, owner, next action
5. **Operator decides** → Escalate to engineering or close if recovered

---

## Validation Checklist

After the quick start:
- ✅ Azure Monitor alert fires (check Alerts page in portal)
- ✅ SRE Agent investigates automatically
- ✅ Application Insights shows failed requests + exceptions + traces
- ✅ Incident summary generated with evidence links
- ✅ Operator can confirm recovery state
- ✅ Incident record ready for escalation

---

## Cleanup

```bash
# Restore the app
APP_URL="$(cd infra/terraform && terraform output -raw orders_api_url)"
curl -X POST "$APP_URL/api/simulate/reset"
```

---

## Next: What Comes After S4

- **S5 — PIM Audit**: Compliance and security audit scenarios
- **S6 — Front Door Incident Response**: CDN-layer incident investigation

## Knowledge Base

- [http-500-errors.md](../../knowledge-base/http-500-errors.md)
- [incident-report.md](../../knowledge-base/incident-report.md)
- [on-call-handoff.md](../../knowledge-base/on-call-handoff.md)
- [orders-architecture.md](../../knowledge-base/orders-architecture.md)
