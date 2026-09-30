# Lab: S2 — AI Web App Production Incident (Autonomous Remediation)

**Persona:** Platform / SRE  
**Time:** ~15 minutes
**Runtime:** Azure App Service (conference default) or Azure Container Apps
**Infrastructure:** Terraform
**Recipe:** `azmon-lawappinsights`

## Learning objectives

In this lab, you will:

- Reproduce a controlled App Service process crash and restore service.
- Investigate with Azure Monitor, Application Insights, Log Analytics, and deployment evidence.
- Verify safe remediation and service recovery.

---

## Prerequisites

Set these values in `tfvars`:

```hcl
scenario                       = "s2"
access_level                   = "High"
action_mode                    = "Autonomous"
enable_app_insights_connector  = true
enable_log_analytics_connector = true
enable_sev01_incident_filter   = true
```

---

## Exercise 1: Deploy and validate baseline

### Task 1: Deploy the environment

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

Deployment does four things:
1. Reads `sbox.tfvars` and applies Terraform
2. Deploys the runtime workload (`orders-api`)
3. Registers runtime-scoped S2 agent extras via `apply-extras.sh` — knowledge base, common
   prompts, hooks, the GitHub repo connection, skills, subagents and the
   response plan
4. Enables autonomous incident handling for S2 response plan

The repo connection is what lets the agent correlate the incident with the
commits and workflow runs behind it, via the `FindConnectedGitHubRepo` tool. The
repository is resolved from `GITHUB_REPOSITORY` in Actions, or the `origin`
remote locally. A first-time connection may need a one-off GitHub authorization
in the portal's Repos blade; the rest of the catalog applies either way.

`apply-extras.sh` reads Terraform's deployed `runtime_stack`, so Web App runs
receive App Service guidance and Container Apps runs receive Container Apps
guidance. The workflow defaults to `webapp`.

### Task 2: Load the backend endpoint and validate baseline

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

### Task 3 (optional): Use Container Apps runtime

Set `runtime=containerapps` in deploy, then load the URL with:

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

> **Caution:** `Autonomous` mode allows write actions. Use only in an isolated lab resource group.

### Guardrails applied for S2

`scripts/apply-extras.sh` registers three `PreToolUse` hooks before the agent can act:

| Hook | Effect |
|------|--------|
| `deny-prod-deletes` | Denies deletes/removes against resources named `prod` or `prd` |
| `require-approval-for-restarts` | Requires human approval to restart, scale or recycle a resource |
| `s2-require-approval-for-deployment-changes` | Requires approval for deployment changes, except setting only `CHAOS_ENABLED=false` on a confirmed S2 lab `orders-api-*` App Service with `CHAOS_MODE=crash` |

The first two apply in every scenario; the third is added only for `scenario=s2`,
because S2 is the scenario that combines `Autonomous` mode with `High` access.
Definitions live in [`recipes/azmon-lawappinsights/config/hooks/`](../../recipes/azmon-lawappinsights/config/hooks/).

---

## Exercise 2: Trigger the incident and observe impact

### Conference path: inject an App Service outage with Chaos Monkey

Use only the isolated S2 lab App Service, not a production website. The deployed
`orders-api` App Service starts with `CHAOS_ENABLED=false` and
`CHAOS_MODE=crash`. Its root currently returns service metadata (not a
dashboard). Enabling chaos terminates the process on startup. The App Service
may restart the container repeatedly, but `/health`, the root, and orders
remain unavailable until the setting is reverted. A dead process cannot emit
new Application Insights request telemetry: the S2 App Service platform
`Http5xx` metric alert is used for this path instead of the application-level
`alert-orders-api-5xx`.

```bash
# Use BACKEND_WEBAPP_NAME, RESOURCE_GROUP and APP_URL from Exercise 1.
curl --fail --silent --show-error "$APP_URL/health"
curl --fail --silent --show-error "$APP_URL/"
az webapp config appsettings list --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_WEBAPP_NAME" \
  --query "[?name=='CHAOS_ENABLED' || name=='CHAOS_MODE'].{name:name,value:value}" \
  --output table
```

Trigger the change interactively with GitHub Copilot CLI. Review and approve
the exact command before execution; do not grant unrestricted tool access:

```bash
copilot -i "For the isolated S2 lab only, run az webapp config appsettings set \
--resource-group $RESOURCE_GROUP --name $BACKEND_WEBAPP_NAME \
--settings CHAOS_ENABLED=true --output none. Show me the exact command \
and wait for my approval. Do not change CHAOS_MODE, other settings or other apps."
```

Once the App Service starts failing, generate platform HTTP 5xx responses:

```bash
for request in {1..12}; do
  curl --silent --output /dev/null \
    --max-time 10 --write-out "website request $request: HTTP %{http_code}\n" "$APP_URL/"
done
curl --silent --output /dev/null \
  --max-time 10 --write-out "/health HTTP %{http_code}\n" "$APP_URL/health"
```

Check that the platform records more than five HTTP 5xx responses in five
minutes and `alert-orders-api-webapp-5xx` fires. If requests time out or do
not produce a platform 5xx, inspect the App Service metric before claiming
the alert fired. The S2 Azure Monitor response plan routes the **Orders API**
Sev1 alert to the triage agent in autonomous mode. Review its evidence:
the app-setting change, failed health and requests, container startup/crash
logs, and `CHAOS_ENABLED=true` with `CHAOS_MODE=crash`.
The only pre-approved autonomous configuration fix is to set
`CHAOS_ENABLED=false` on this isolated lab's `orders-api-*` App Service. All
other deployment changes and explicit restarts still require human approval.
Verify that `/health`, the root and `/api/orders` succeed and 5xx returns to baseline;
do not claim remediation occurred until the agent action and recovery are
observed. If the agent does not act, restore the lab manually:

```bash
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKEND_WEBAPP_NAME" \
  --settings CHAOS_ENABLED=false \
  --output none
```

### Alternative: use GitHub Copilot CLI to introduce a backend-only regression

The regression is driven by the `orders-api` simulation endpoints, which are part of
the deployed image. Let Copilot CLI draft and run the calls so the demo shows an
operator working in natural language rather than pasting curl.

Copilot needs the backend URL, so export it first (Exercise 1 already set `APP_URL`):

```bash
echo "$APP_URL"
```

Interactive — Copilot proposes each command and waits for your approval:

```bash
copilot -i "Against the orders-api at $APP_URL, POST to /api/simulate/active-cr/CHG0030001 \
to mark an active change window, then POST to /api/simulate/failure-rate/100 so /api/orders \
starts returning HTTP 500. Then send 30 POSTs to /api/orders with a JSON body of \
{\"customerId\":\"lab-user\",\"sku\":\"S2-DEMO\",\"quantity\":1} and print each status code."
```

> **Why these two calls:** `active-cr` stamps a change-request id into the forced 500
> response detail, which is the evidence the agent correlates against deployment history
> in Exercise 3. `failure-rate/100` is deterministic — the App Service stays **Running**
> and `/health` keeps passing, so the incident presents as a backend-only regression.

Scripted — non-interactive mode requires `--allow-all-tools`, so use it only in the
isolated lab resource group:

```bash
copilot -p "Against the orders-api at $APP_URL, POST /api/simulate/active-cr/CHG0030001, \
then POST /api/simulate/failure-rate/100, then send 30 POSTs to /api/orders and report \
how many returned 500." --allow-all-tools
```

<details>
<summary>Fallback: run the same calls directly with curl</summary>

```bash
# Mark the change window so forced 500s carry a correlatable CR id
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/simulate/active-cr/CHG0030001"

# Break the backend: force /api/orders to return HTTP 500
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
```

</details>

### Task 2: Confirm the incident signature

The alert rule `alert-orders-api-5xx` queries the Application Insights `requests` table
for `orders-api` 5xx responses, so the failing requests above are what arms it. Confirm
the regression is backend-only:

```bash
# App Service still reports Running and /health still passes
curl --fail --silent --show-error "$APP_URL/health"

# /api/orders is the only thing failing
curl --silent --output /dev/null \
  --write-out "/api/orders during incident: HTTP %{http_code}\n" \
  -X POST "$APP_URL/api/orders" \
  -H "Content-Type: application/json" \
  --data '{"customerId":"lab-user","sku":"S2-DEMO","quantity":1}'
```

> **Do not** use `az webapp stop` to trigger either scenario. For a process
> crash, use the App Service `Http5xx` metric alert; for backend-only failure,
> use the Application Insights `alert-orders-api-5xx` rule.

---

## Exercise 3: Investigate and remediate

Use this lab incident flow:

**Detect → Investigate → Correlate → Diagnose → Remediate → Verify**

### Verify recovery

Once the agent has remediated, confirm the runtime is healthy and the simulation is no
longer forcing failures.

```bash
RUNTIME="${RUNTIME:-webapp}"  # set to containerapps when using that runtime
if [ "$RUNTIME" = "webapp" ]; then
  BACKEND_WEBAPP_NAME="$(az webapp list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'orders-api')].name | [0]" \
    --output tsv)"
  az webapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$BACKEND_WEBAPP_NAME" \
    --query "{state:state,host:defaultHostName}" \
    --output table
else
  CONTAINERAPP_NAME="$(az containerapp list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?starts_with(name, 'orders-api')].name | [0]" \
    --output tsv)"
  az containerapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINERAPP_NAME" \
    --query "{state:properties.provisioningState,revision:properties.latestRevisionName}" \
    --output table
fi

# Shared recovery checks for either runtime
curl --fail --silent --show-error "$APP_URL/health"
curl --fail --silent --show-error "$APP_URL/"
curl --fail --silent --show-error \
  -X POST "$APP_URL/api/orders" \
  -H "Content-Type: application/json" \
  --data '{"customerId":"verify-user","sku":"VERIFY","quantity":1}'
```

These checks fail while the crash incident is still active — that is the signal
remediation has not completed yet.

---

## Scenario context

Conference default: **App Service**.  
Alternate runtime: **Container Apps** with the same `/api/orders` failure symptoms and runtime-specific telemetry correlation.

A new `orders-api` backend version is deployed to production.
In the backend-only variant the App Service root still loads, but backend calls
start failing. In the conference Chaos Monkey variant, the worker crashes on
startup and all endpoints fail until the setting is restored.
Soon after deployment:

- App Service container repeatedly fails to start
- `/health`, `/`, and `/api/orders` are unavailable
- App Service platform `Http5xx` metric crosses the alert threshold
- app settings and crash logs align with the incident start

This lab demonstrates autonomous incident handling with evidence-driven remediation.

---

## Investigation path

1. **Detect** → Azure Monitor incident opens on App Service platform 5xx
2. **Investigate** → Traverse Azure Monitor → App Service startup logs and settings
3. **Correlate** → Align first-failure time with the app-setting change
4. **Diagnose** → Confirm the lab-only Chaos Monkey process crash
5. **Remediate** → Revert only `CHAOS_ENABLED` on the isolated lab app
6. **Verify** → Confirm `/health`, the root and `/api/orders` recover

---

## Reference architecture

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

## Exercise 4: UI demo sequence

1. Show the App Service root, `/health`, and order requests working.
2. Enable the isolated lab's `CHAOS_ENABLED` app setting.
3. Show the website and health check failing after the worker crashes.
4. Show Azure Monitor incident firing on App Service platform 5xx.
5. Show SRE Agent investigation trail across metrics, startup logs and settings.
6. Optionally delegate backend diagnosis to a specialist sub-agent.
7. Observe autonomous setting reversal and refresh the endpoint to confirm recovery.

---

## Validation Checklist

After the quick start:
- ✅ App Service `Http5xx` alert fires after the metric threshold is crossed
- ✅ Agent correlates incident timing to recent deployment/change context
- ✅ RCA names first-failure time, the correlated change, and the delta between them
- ✅ RCA renders a numbered 5-Whys ladder with the trigger and latent cause stated separately
- ✅ App Service startup logs and platform metrics show the outage (application telemetry stops)
- ✅ Agent proposes or applies safe remediation
- ✅ `/health` and `/api/orders` recover
- ✅ 5xx rate returns to baseline

---

## Cleanup

```bash
# Restore the runtime simulation if the agent has not already remediated it.
# You can use GitHub Copilot CLI to draft the reset command the same way.
# For the App Service Chaos Monkey path, set CHAOS_ENABLED=false as shown above.
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
