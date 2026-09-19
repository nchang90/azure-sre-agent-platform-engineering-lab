# Orders Platform Architecture (Knowledge Base Entry)

This catalog entry is used by scenario setup to provide architecture context for
Orders API incident triage and remediation.

## Core Components

- `orders-api` (Azure App Service for S2 conference path, Container Apps supported): customer-facing Orders service.
- `change-lookup` (Azure Container Apps): maps active/recent change requests.
- Shared observability: Application Insights + Log Analytics.

## Incident Correlation Context

When investigating 5xx incidents:

1. Read `orders-api /health` and probe `POST /api/orders` with a minimal valid payload (for example `{"customerId":"baseline-user","sku":"BASELINE","quantity":1}`) to confirm endpoint-specific impact.
2. Correlate alert timestamps with recent deployment/revision/swap events.
3. Use change context (active CR) to validate whether a recent rollout is the likely trigger.
4. Confirm dependency health before choosing rollback, config correction, or scale actions.

## Detailed Reference

For full architecture details, endpoints, and telemetry guidance, see:
- `knowledge-base/runbooks/containers/orders-architecture.md`
