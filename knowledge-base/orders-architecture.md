# Orders Platform Architecture (Knowledge Base Entry)

This catalog entry is used by scenario setup to provide architecture context for
Orders API incident triage and remediation.

## Core Components

- `orders-api` (Azure Container Apps): customer-facing Orders service.
- `change-lookup` (Azure Container Apps): maps active/recent change requests.
- Shared observability: Application Insights + Log Analytics.

## Incident Correlation Context

When investigating 5xx incidents:

1. Read `orders-api /health` to confirm runtime status.
2. Correlate alert timestamps with recent revision/deployment events.
3. Use change context (active CR) to validate whether a recent rollout is the likely trigger.
4. Confirm dependency health before choosing rollback or scale actions.

## Detailed Reference

For full architecture details, endpoints, and telemetry guidance, see:
- `knowledge-base/runbooks/containers/orders-architecture.md`
