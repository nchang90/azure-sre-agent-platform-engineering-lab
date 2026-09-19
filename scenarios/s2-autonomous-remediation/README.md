# S2 — Web API Production Deployment Regression (Autonomous Remediation)

**Persona:** Platform / SRE  
**Time:** ~15 minutes
**Runtime:** Azure App Service (conference default) or Azure Container Apps
**Infrastructure:** Terraform
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup

Set these values in `tfvars`:

```hcl
scenario                       = "s2"
access_level                   = "High"
action_mode                    = "Autonomous"
enable_app_insights_connector  = true
enable_log_analytics_connector = true
enable_sev01_incident_filter   = true
```

Then deploy the environment:

```bash
# The workflow reads sbox.tfvars, deploys Terraform and application images,
# then apply-extras.sh detects scenario=s2 and registers the S2 catalog.
gh workflow run deploy.yml \
  -f environment=sbox \
  -f runtime=webapp \
  -f plan=true \
  -f apply=true

gh run watch

# Load the deployed application details
RESOURCE_GROUP="rg-sre-lab-sbox"
APP_NAME="orders-api"
APP_FQDN="$(az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query defaultHostName \
  --output tsv)"
APP_URL="https://$APP_FQDN"

# Verify the app and API are healthy
az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query "{state:state,host:defaultHostName}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/orders" \
  -H "Content-Type: application/json" \
  --data '{"customerId":"warmup-user","sku":"WARMUP","quantity":1}'
```

To run S2 on Container Apps instead, set `runtime=containerapps` and load the URL with:

```bash
APP_FQDN="$(az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query properties.configuration.ingress.fqdn \
  --output tsv)"
APP_URL="https://$APP_FQDN"
az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query "{state:properties.provisioningState,revision:properties.latestRevisionName}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
```

> **Caution:** `Autonomous` mode allows the agent to perform write actions. Use only
> in the isolated lab resource group. Return to `Review` mode after the exercise.

### Simulate production-style regression and observe (5 mins)
```bash
# Simulate a deployment window correlation
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/active-cr/CHG0030001"

# Simulate a post-deployment regression impact on /api/orders
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/failure-rate/100"

# Generate failed requests so the 5xx alert threshold is reached
for request in {1..30}; do
  curl --silent --output /dev/null \
    --write-out "request $request: HTTP %{http_code}\n" \
    -X POST "$APP_URL/api/orders" \
    -H "Content-Type: application/json" \
    --data '{"customerId":"lab-user","sku":"S2-DEMO","quantity":1}'
done

# Verify service after remediation
az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query "{state:state,lastModified:lastModifiedTimeUtc}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
```

---

## Incident Story

A new `orders-api` web API version is deployed to production. Soon after deployment:

- App Service still reports **Running**
- CPU and memory remain near baseline
- `/health` still passes
- `/api/orders` starts returning HTTP 500
- Application Insights exceptions rise
- dependency failures increase
- 5xx rate crosses the alert threshold
- deployment history aligns with incident start

S2 demonstrates the autonomous path:
**Detect → Investigate → Correlate → Diagnose → Remediate → Verify**.

---

## How It Works

1. **Detect** → Azure Monitor incident opens on `/api/orders` 5xx spike
2. **Investigate** → Query failed requests, exceptions, and dependencies in App Insights
3. **Correlate** → Align first-failure time with recent deployment/change window
4. **Diagnose** → Identify likely regression class
5. **Remediate** → Apply the safest reversible remediation for confirmed cause
6. **Verify** → Confirm `/health`, `/api/orders`, dependency success, and 5xx recovery

---

## Architecture

<img src="../../images/s2-autonomous-remediation.svg" alt="S2 autonomous remediation workflow diagram" width="700" />

Production framing:

`Client → Azure App Service → orders-api → Azure SQL / external dependency → Application Insights`

---

## Failure Variants for Conference Demo

Preferred deep-investigation variants:

- **A. Bad application configuration (recommended)**  
  New deployment introduces invalid App Settings/connection configuration.
- **B. Database connection regression (recommended)**  
  New version uses incorrect DB connection configuration.

Additional variants:

- **C. Dependency timeout** — downstream dependency latency causes request timeouts and cascading 5xx.
- **D. Code regression** — endpoint-specific exception introduced by new release.
- **E. Slot configuration drift** — swap leaves production missing/incorrect settings present in staging.

---

## Validation Checklist

After the quick start:
- ✅ Alert fires in 30–60 seconds
- ✅ Agent correlates incident timing to recent deployment/change context
- ✅ Application Insights shows request failures, exceptions, and dependency impact
- ✅ Agent proposes or applies safe remediation
- ✅ `/health` and `/api/orders` recover
- ✅ 5xx rate returns to baseline

---

## Cleanup

```bash
# Restore the runtime simulation if the agent has not already remediated it
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/reset"

curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/clear-cr"
```

---

## Next: What Comes After S2

- **S3 — AKS Multi-Agent Investigation**: Delegate AKS state/routing diagnostics to specialist subagents
- **S4 — Alert Response**: Operator-ready monitoring workflows
- **S5 — PIM Audit**: Compliance and security audit scenarios
