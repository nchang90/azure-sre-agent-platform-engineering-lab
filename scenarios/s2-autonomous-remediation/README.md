# S2 — AI Web App Production Incident (Autonomous Remediation)

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
```

Deploy does four things (similar to Foundry app quick start style):
1. Reads `sbox.tfvars` and applies Terraform
2. Deploys the runtime workload (`orders-api`)
3. Registers S2 agent extras via `apply-extras.sh`
4. Enables autonomous incident handling for S2 response plan

Then load the deployed backend API details:

```bash
ENVIRONMENT="sbox"
RESOURCE_GROUP="rg-sre-lab-$ENVIRONMENT"
BACKEND_WEBAPP_NAME="$(az webapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'orders-api')].name | [0]" \
  --output tsv)"
APP_FQDN="$(az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_WEBAPP_NAME" \
  --query defaultHostName \
  --output tsv)"
APP_URL="https://$APP_FQDN"

# Verify the app and API baseline
az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_WEBAPP_NAME" \
  --query "{state:state,host:defaultHostName}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
curl --silent --output /dev/null \
  --write-out "baseline /api/orders HTTP %{http_code}\n" \
  -X POST "$APP_URL/api/orders" \
  -H "Content-Type: application/json" \
  --data '{"customerId":"baseline-user","sku":"BASELINE","quantity":1}'
```

To run S2 on Container Apps instead, set `runtime=containerapps` and load the URL with:

```bash
ENVIRONMENT="sbox"
RESOURCE_GROUP="rg-sre-lab-$ENVIRONMENT"
CONTAINERAPP_NAME="$(az containerapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'orders-api')].name | [0]" \
  --output tsv)"
APP_FQDN="$(az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINERAPP_NAME" \
  --query properties.configuration.ingress.fqdn \
  --output tsv)"
APP_URL="https://$APP_FQDN"
az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINERAPP_NAME" \
  --query "{state:properties.provisioningState,revision:properties.latestRevisionName}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
```

> **Caution:** `Autonomous` mode allows the agent to perform write actions. Use only
> in the isolated lab resource group. Return to `Review` mode after the exercise.

### Simulate production incident and observe (5 mins)
```bash
# Simulate a deployment window correlation
# Prerequisite check in deployed environment:
# HTTP 200 => simulation route is available
# HTTP 404/405 => skip this step and correlate with deployment history + telemetry only
ACTIVE_CR_STATUS="$(curl --silent --output /dev/null --write-out "%{http_code}" \
  -X POST "$APP_URL/api/simulate/active-cr/CHG0030001")"
echo "active-cr route HTTP $ACTIVE_CR_STATUS"
if [ "$ACTIVE_CR_STATUS" != "200" ]; then
  echo "Skipping active change-correlation simulation; use deployment history + telemetry timestamps."
fi

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

# Verify runtime state after remediation (choose one)
# Option A: runtime=webapp
BACKEND_WEBAPP_NAME="$(az webapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'orders-api')].name | [0]" \
  --output tsv)"
az webapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_WEBAPP_NAME" \
  --query "{state:state,host:defaultHostName}" \
  --output table

# Option B: runtime=containerapps
CONTAINERAPP_NAME="$(az containerapp list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?starts_with(name, 'orders-api')].name | [0]" \
  --output tsv)"
az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINERAPP_NAME" \
  --query "{state:properties.provisioningState,revision:properties.latestRevisionName}" \
  --output table

# Shared recovery checks for either runtime
curl --fail --silent --show-error "$APP_URL/health"
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/orders" \
  -H "Content-Type: application/json" \
  --data '{"customerId":"verify-user","sku":"VERIFY","quantity":1}'
```

---

## Incident Story

Conference default: **App Service**.  
Alternate runtime: **Container Apps** with the same `/api/orders` failure symptoms and runtime-specific telemetry correlation.

A new `orders-api` backend version is deployed to production.
The UI dashboard still loads, but backend calls start failing.
Soon after deployment:

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

1. **Detect** → Azure Monitor incident opens on `web-api` 5xx threshold breach
2. **Investigate** → Traverse evidence chain: Azure Monitor → App Service → Application Insights → web-api → deployment history
3. **Correlate** → Align first-failure time with recent deployment/change window
4. **Diagnose** → Identify likely regression class
5. **Remediate** → Apply safest reversible remediation for confirmed cause
6. **Verify** → Confirm dashboard backend calls recover, `/api/orders` succeeds, and 5xx returns to baseline

---

## Architecture

<img src="../../images/s2-autonomous-remediation.svg" alt="S2 autonomous remediation workflow diagram" width="700" />

Production framing:

`User → Web App (dashboard) → web-api → Foundry Agent`

Operational overlays:
- Entra ID for sign-in and access control
- Application Insights + Log Analytics for request, exception, and dependency telemetry
- Azure Monitor alerting for backend 5xx thresholds
- Deployment history and change context for incident correlation

Backend dependency chain remains:

`Client/UI → App Service web-api → Azure SQL / external dependency → Application Insights`

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

## UI Demo Sequence (Conference Friendly)

1. Open the dashboard and show normal UX.
2. Introduce controlled backend regression.
3. Show frontend still renders while backend actions fail.
4. Show Azure Monitor incident firing on `web-api` 5xx.
5. Show SRE Agent investigation trail across telemetry + deployment evidence.
6. Optionally delegate backend diagnosis to a specialist sub-agent.
7. Apply safe remediation and refresh dashboard to confirm recovery.

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
