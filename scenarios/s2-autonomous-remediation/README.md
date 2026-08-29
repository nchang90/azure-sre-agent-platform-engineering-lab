# S2 — Autonomous Remediation (Runtime Scenario)

**Persona:** Platform / SRE  
**Time:** ~10 minutes (after S1)  
**Prerequisite:** S1 infrastructure deployed  
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup
```bash
# S1 infrastructure must be running
# Verify orders-api service is healthy
kubectl get pods -n default | grep orders-api
# Expected: 3 replicas, all Running ✅
```

### Deploy & Observe (5 mins)
```bash
# Verify SRE Agent is ready
az resource show --resource-group s1-demo-rg --name s1-agent \
  --resource-type "Microsoft.App/agents@2025-05-01-preview"

# Trigger incident at runtime (no code/infra changes)
# Option A: Scale down replicas to cause load errors
kubectl scale deployment orders-api --replicas=0 -n default

# Option B: Call a broken endpoint
ENDPOINT=$(kubectl get svc orders-api -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -X POST http://$ENDPOINT/api/orders/break

# Watch it auto-respond:
# - Alert fires (30–60 sec)
# - SRE Agent investigates via Application Insights
# - Proposes remediation (scale up, restart, or drain)
# - Executes fix automatically or waits for approval
# - Service recovers

# Verify incident resolved
kubectl get pods -n default | grep orders-api
# Expected: Replicas back to 3, all Running ✅
```

---

## Story

Break the running app with a single command, then watch the SRE Agent respond end-to-end: **detect** the 5xx spike, **investigate** the root cause, **propose** a remediation, and optionally **execute the fix**. No infrastructure changes—just pure runtime scenario against the already-deployed orders-api.

---

## How It Works

1. **Inject failure** → Scale down or call broken endpoint
2. **Alert fires** → Application Insights detects 5xx spike
3. **Agent investigates** → Runs queries for error context and resource metrics
4. **Proposes fix** → Scale up replicas, restart pods, or drain nodes
5. **Executes** → Auto-fix (or wait for human approval)
6. **Confirms recovery** → Re-checks health and metrics

---

## Validation Checklist

After the quick start:
- ✅ Alert fires in 30–60 seconds
- ✅ SRE Agent investigates automatically
- ✅ Application Insights shows error spike + recovery
- ✅ Remediation actions proposed or executed
- ✅ Pod replicas scale back to 3
- ✅ Error rate drops to baseline

---

## Cleanup

```bash
# Restore the app
APP_URL="$(cd infra/terraform && terraform output -raw orders_api_url)"
curl -X POST "$APP_URL/api/simulate/reset"
```

---

## Next: What Comes After S2

- **S3 — AKS Root Cause**: ServiceNow integration + Kubernetes investigation
- **S4 — Alert Response**: Operator-ready monitoring workflows
- **S5 — PIM Audit**: Compliance and security audit scenarios
