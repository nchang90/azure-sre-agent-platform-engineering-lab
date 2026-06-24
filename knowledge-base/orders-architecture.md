# Orders Platform — Service Architecture

## Owner

| | |
|---|---|
| Product team | **Orders Platform** (owns `orders-api`) |
| Platform team | Owns the Internal Developer Platform: `change-portal`, `change-lookup`, the SRE Agent, ACR, Container Apps Environment, and shared observability |
| On-call | Orders Platform during business hours, Platform team escalation after-hours |

The Platform team's job here is to provide a **paved road**: any product team
deploying to the shared Container Apps Environment must go through the
change-portal, which enforces a linked ServiceNow Change Request (CR) before a
new revision is allowed to ship.

---

## Infrastructure (Platform-managed)

| Component | Azure Service | Owner | Details |
|-----------|---------------|-------|---------|
| **orders-api** | Azure Container Apps | Orders Platform | .NET 9 API, port 8080, external ingress |
| **change-portal** | Azure Container Apps | Platform team | Self-service deploy UI for product teams |
| **change-lookup** | Azure Container Apps | Platform team | ServiceNow CR proxy used by the SRE Agent |
| **Container Environment** | Container Apps Environment | Platform team | Shared by all product apps |
| **Registry** | Azure Container Registry | Platform team | All images for the platform |
| **Logs** | Log Analytics Workspace | Platform team | `ContainerAppConsoleLogs_CL` |
| **Telemetry** | Application Insights | Platform team | Shared APM endpoint |
| **Identity** | User-Assigned Managed Identity | Platform team | Reader + Monitoring Reader + Log Analytics Reader on the platform RG |
| **Alerts** | Azure Monitor | Platform team | Wired to the SRE Agent's Alert Handlers |

---

## API Endpoints (orders-api)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Service metadata (includes `activeChangeRequest`) |
| `/health` | GET | Health status (includes `activeChangeRequest`) |
| `/api/orders` | POST | Creates a simulated order |
| `/api/orders/{id}` | GET | Gets order status |
| `/api/orders/fail` | GET | Forced 500 — quick way to fire alerts |
| `/api/simulate/failure-rate/{percent}` | POST | Sets runtime failure rate (0-100) |
| `/api/simulate/reset` | POST | Resets runtime failure simulation |
| `/api/simulate/active-cr/{cr}` | POST | Announce the CR currently rolling out |
| `/api/simulate/clear-cr` | POST | Clear the active CR |

The `activeChangeRequest` field on `/` and `/health` is set by the
**change-portal deploy pipeline** when a deploy ships. The SRE Agent reads this
to correlate alerts with the specific CR a product team is rolling out.

---

## Paved Road for Deploys

```
┌────────────────┐     ┌────────────────┐     ┌────────────────┐
│ Product team   │────▶│ change-portal  │────▶│ ACR + Container│
│ submits deploy │     │ checks CR      │     │ Apps revision  │
│ via portal     │     │ in change-     │     │ activated      │
└────────────────┘     │ lookup         │     └────────┬───────┘
                       └────────────────┘              │
                                                       ▼
                                       ┌─────────────────────────┐
                                       │ /health surfaces        │
                                       │ activeChangeRequest=CHG │
                                       └─────────────────────────┘
```

Deploys without an authorized CR are **flagged as unauthorized** by
change-portal. The SRE Agent treats these as Sev2 incidents per the
[change-management runbook](./change-management-runbook.md).

---

## Fault Injection — Simulated 5xx Surge

Useful when validating new alert rules or rehearsing on-call:

```bash
APP_URL="https://<orders-api-url>"

# Announce the active change window (what the deploy pipeline normally does)
curl -X POST "$APP_URL/api/simulate/active-cr/CHG0030001"

for i in {1..50}; do
  curl -X POST "$APP_URL/api/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"cust-'$i'","sku":"SKU-001","quantity":1}'
done

# Reset
curl -X POST "$APP_URL/api/simulate/reset"
curl -X POST "$APP_URL/api/simulate/clear-cr"
```

---

## Source Code

- **Repository:** connected through the GitHub OAuth code repo integration
- **Language:** .NET 9 minimal API
- **Image:** `orders-api:latest`

### Key Files

| File | Purpose |
|------|---------|
| `src/orders-api/Program.cs` | API routes, failure simulation, active-CR announcement |
| `src/orders-api/OrdersApi.csproj` | Project definition |
| `src/orders-api/appsettings.json` | Logging and simulation defaults |
| `src/orders-api/Dockerfile` | Container build definition |

---

## Monitoring & Alerting

### Log Analytics query

```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where ContainerAppName_s == "orders-api"
| where Log_s contains "error" or Log_s contains "500" or Log_s contains "failed"
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Alert rules (managed by Platform team)

| Alert | Trigger | Severity | Owner |
|-------|---------|----------|-------|
| Orders API 5xx errors | > 5 requests with 5xx status in 5 min | Sev3 | Orders Platform |
| Orders API health check failing | Probe failures in 5 min | Sev2 | Orders Platform |

When either alert fires, the SRE Agent should:

1. Read `/health` from orders-api to capture `activeChangeRequest`
2. Call `change-lookup /changes/{cr}` for context (or `/changes/active/now`)
3. Apply the [change-management runbook](./change-management-runbook.md)

---

## Troubleshooting Quick Reference

1. Check health: `curl https://<app-url>/health` — note `activeChangeRequest`
2. Check simulated failure mode: POST `/api/simulate/failure-rate/{percent}`
3. Query `ContainerAppConsoleLogs_CL` for orders errors
4. Check the active CR: `curl https://<change-lookup-url>/changes/active/now`
5. Roll back revision: `az containerapp update -g <rg> -n orders-api --revision-suffix prev`
