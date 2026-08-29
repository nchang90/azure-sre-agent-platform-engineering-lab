# S6 — Front Door Incident Response

**Persona:** Platform / On-call  
**Time:** ~15 minutes  
**Prerequisite:** S1 infrastructure deployed  
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup
```bash
# S1 infrastructure must be running
# Verify Front Door and Container Apps are deployed
az containerapp list --resource-group s1-demo-rg
```

### Deploy & Observe (5 mins)
```bash
# Register S6 incident response automation
bash scripts/apply-extras.sh s6

# Trigger incident: simulate Front Door routing misconfiguration
# Scale down replicas to cause health probe failures
az containerapp scale \
  --resource-group s1-demo-rg \
  --name orders-api \
  --target 0

# Watch it auto-respond:
# - Azure Monitor alert fires (30–60 sec for health check failure)
# - SRE Agent investigates via Application Insights
# - Identifies Front Door routing issue
# - Proposes remediation (scale replicas, check routing rule)
# - Executes fix (or waits for approval)
# - Service recovers and traffic restored through Front Door

# Verify incident resolved
az containerapp scale \
  --resource-group s1-demo-rg \
  --name orders-api \
  --target 3
```

---

## Story

A Platform team misconfigures Azure Front Door routing rules, causing health probes to fail and end-user traffic to hit 502/503 errors. The SRE Agent automatically detects the spike, diagnoses the multi-layer issue (Front Door → Container Apps → health endpoint), proposes remediation, and optionally executes the fix. Traffic is restored before on-call escalates.

---

## How It Works

1. **Alert fires** → Azure Monitor detects 502/503 spike at Front Door edge
2. **Agent investigates** → Queries Application Insights + Front Door metrics
3. **Diagnoses** → Correlates health probe failures with routing misconfiguration
4. **Proposes fix** → Scale replicas, update routing rule, or failover
5. **Executes** → Auto-fix (or wait for human approval)

---

## Validation Checklist

After the quick start:
- ✅ Azure Monitor alert fires (check Alerts page in portal)
- ✅ SRE Agent investigates automatically
- ✅ Application Insights shows 502/503 spike + recovery
- ✅ Front Door health probe metrics show failure → recovery
- ✅ Container Apps replicas scale back to 3
- ✅ Error rate drops to baseline

---

## Cleanup

```bash
# Restore replicas if needed
az containerapp scale \
  --resource-group s1-demo-rg \
  --name orders-api \
  --target 3
```

---

## Next: What Comes After S6

**You've completed all 6 scenarios!**
- S1–S2 cover core incident detection and autonomous remediation
- S3 covers AKS root cause investigation with ServiceNow
- S4 covers operator workflows
- S5 covers compliance auditing
- S6 covers CDN-layer incident response

---

## Knowledge Base

- [http-502-errors.md](../../knowledge-base/http-502-errors.md)
- [frontdoor-architecture.md](../../knowledge-base/frontdoor-architecture.md)
- [incident-report.md](../../knowledge-base/incident-report.md)
