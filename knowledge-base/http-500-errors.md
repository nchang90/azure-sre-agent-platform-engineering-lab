# Orders API HTTP 500 Incident Playbook (S2)

Use this runbook for S2 production incidents where `orders-api` starts returning HTTP 500s after a deployment.
Follow the flow: **detect → investigate → correlate → diagnose → remediate → verify**.

## Architecture and incident shape

`Client → Azure App Service → web-api → Azure SQL / external dependency → Application Insights`

Expected symptom pattern:
- App Service still shows `Running`
- CPU/memory remain normal
- `/health` may still pass
- `/api/orders` returns 500
- exceptions and dependency failures rise
- 5xx alert crosses threshold shortly after deployment

## 1) Detect

- Confirm the incident trigger (Azure Monitor alert / App Insights 5xx SLO breach).
- Capture first-seen time, impacted endpoint(s), and current 5xx rate.

## 2) Investigate

- Check endpoint health and blast radius:
  - `GET /health`
  - `POST /api/orders`
- Review telemetry in App Insights:
  - failed requests (`resultCode startswith "5"`)
  - exceptions (`exceptions`)
  - failing/slow dependencies (`dependencies`)

## 3) Correlate

- Align first-failure time with:
  - recent App Service deployments, swaps, or revision changes
  - active change request context from `change-lookup`
  - dependency degradation windows
- Keep facts separate from hypotheses.

## 4) Diagnose

Prioritize these regression variants:
1. Bad application configuration.
2. Database connection regression.
3. Dependency timeout.
4. Endpoint-specific code regression.
5. Slot configuration drift after swap.

## 5) Remediate (safe and reversible first)

1. Roll back to last known healthy deployment if regression is deployment-linked.
2. Correct confirmed app settings / connection configuration drift.
3. Restart the app only for transient runtime faults.
4. Apply dependency timeout/scale mitigations only when backed by telemetry.

If action mode is **Review**, request approval before write actions.

## 6) Verify recovery

- Confirm:
  - `/health` and `/api/orders` recover
  - dependency failures return to baseline
  - 5xx and exception rates drop
  - alert condition clears
- Record root cause, evidence, remediation, and follow-up actions.

## Detailed reference

For expanded KQL/CLI procedures, see:
- `knowledge-base/runbooks/containers/http-500-errors.md`
