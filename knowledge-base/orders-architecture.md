# Orders Platform Architecture (Knowledge Base Entry)

This catalog entry is used by scenario setup to provide architecture context for
Orders API incident triage and remediation.

## Core Components

- `web-dashboard` (small frontend on Web App): user-facing UI that calls `orders-api`.
- `orders-api` (Azure App Service for S2 conference path, Container Apps supported): customer-facing Orders service.
- `change-lookup` (Azure Container Apps): maps active/recent change requests.
- `Foundry Agent` (downstream dependency): AI/backend agent integration used by the web flow.
- Shared observability: Application Insights + Log Analytics.
- Security and identity: Entra ID sign-in and access control.

Dashboard URL source of truth for incident triage:
- Primary source: deployment outputs/portal for the active demo environment.
- In this lab, backend runtime commands target `orders-api`; frontend URL discovery is separate from backend resource lookup.
- If a dedicated dashboard Web App is deployed, discover it with:
  - `az webapp list -g <resource-group> --query "[?starts_with(name, 'web-dashboard')].defaultHostName | [0]" -o tsv`
- If no dedicated dashboard app exists in the environment, use the conference operator-provided dashboard URL.

## Incident Correlation Context

When investigating 5xx incidents:

1. Read `orders-api /health` and probe `POST /api/orders` with a minimal valid payload (for example `{"customerId":"baseline-user","sku":"BASELINE","quantity":1}`) to confirm endpoint-specific impact.
2. Confirm UI behavior: dashboard still loads while backend operations fail.
3. Correlate alert timestamps with recent deployment/revision/swap events.
4. Use change context (active CR) to validate whether a recent rollout is the likely trigger.
5. Confirm dependency health (including Foundry Agent/downstream calls) before choosing rollback, config correction, or scale actions.

## Detailed Reference

For full architecture details, endpoints, and telemetry guidance, see:
- `knowledge-base/runbooks/containers/orders-architecture.md`
