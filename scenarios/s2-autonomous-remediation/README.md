# S2 — Autonomous Remediation (Runtime Scenario)

**Persona:** Platform / SRE  
**Time:** ~15 minutes
**Runtime:** Azure Container Apps
**Infrastructure:** Terraform
**Recipe:** `azmon-lawappinsights`

---

## ⚡ Quick Start: 5-Minute Lab

### Prerequisites & Setup

Set these values in `tfvars`:

```hcl
scenario                       = "s2"
access_level                   = "High"
action_mode                    = "Automatic"
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
  -f plan=true \
  -f apply=true

gh run watch

# Load the deployed application details
RESOURCE_GROUP="rg-sre-lab-sbox"
APP_NAME="orders-api"
APP_FQDN="$(az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query properties.configuration.ingress.fqdn \
  --output tsv)"
APP_URL="https://$APP_FQDN"

# Verify the Container App and API are healthy
az containerapp show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query "{state:properties.provisioningState,revision:properties.latestRevisionName}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
```

> **Caution:** `Automatic` mode allows the agent to perform write actions. Use only
> in the isolated lab resource group. Return to `Review` mode after the exercise.

### Deploy & Observe (5 mins)
```bash
# Inject a 100% order-processing failure at runtime
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/failure-rate/100"

# Generate failed requests so the alert threshold is reached
for request in {1..30}; do
  curl --silent --output /dev/null \
    --write-out "request $request: HTTP %{http_code}\n" \
    -X POST "$APP_URL/api/orders" \
    -H "Content-Type: application/json" \
    --data '{"customerId":"lab-user","sku":"S2-DEMO","quantity":1}'
done

# Verify the active revision and API after remediation
az containerapp revision list \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_NAME" \
  --query "[?properties.active].{revision:name,replicas:properties.replicas}" \
  --output table
curl --fail --silent --show-error "$APP_URL/health"
```

---

## Story

Unlike S1, which introduces the platform through Bicep and `azd`, S2 uses the
Terraform environment to deploy the Orders API and an SRE Agent with `High`
access in `Automatic` mode. Break the running Container App with a single API
call, then watch the agent **detect** the 5xx spike, **investigate** the root
cause, **execute** a safe remediation, and verify recovery without waiting for
human approval.

---

## How It Works

1. **Inject failure** → Set the Orders API runtime failure rate to 100%
2. **Alert fires** → Application Insights detects 5xx spike
3. **Agent investigates** → Correlates telemetry, Container Apps logs, and revision state
4. **Proposes fix** → Reset the simulation or restart the active revision
5. **Executes** → Applies the safe fix automatically
6. **Confirms recovery** → Re-checks health and metrics

---

## Architecture

<img src="../../images/s2-autonomous-remediation.svg" alt="S2 autonomous remediation workflow diagram" width="700" />

---

## Validation Checklist

After the quick start:
- ✅ Alert fires in 30–60 seconds
- ✅ SRE Agent investigates automatically
- ✅ Application Insights shows error spike + recovery
- ✅ Remediation actions proposed or executed
- ✅ Active Container Apps revision remains healthy
- ✅ Error rate drops to baseline

---

## Cleanup

```bash
# Restore the runtime simulation if the agent has not already remediated it
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/reset"
```

---

## Next: What Comes After S2

- **S3 — AKS Root Cause**: ServiceNow integration + Kubernetes investigation
- **S4 — Alert Response**: Operator-ready monitoring workflows
- **S5 — PIM Audit**: Compliance and security audit scenarios
