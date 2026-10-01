# Orders API HTTP 500 Incident Playbook (S2)

Use this runbook for S2 production incidents where `orders-api` starts returning HTTP 500s after a deployment.
Follow the flow: **detect → investigate → correlate → diagnose → remediate → verify**.

## Architecture and incident shape

`User → Nordic Integration Summit website (served by orders-api) → Azure App Service orders-api → Foundry Agent / Azure SQL / external dependency → Application Insights (+ Log Analytics)`

Expected symptom pattern (App Service conference path):
- `CHAOS_MODE=crash` and `CHAOS_ENABLED=true` take the worker down: it still
  starts, but every route returns HTTP 503
- the website (`/`), `/api/info`, `/health` and `/api/orders` all return 503
- the App Service platform `Http5xx` metric alert fires when enough requests receive 5xx
- app-setting history and the worker's `CHAOS:` critical log lines identify the change

`orders-api` serves the Nordic Integration Summit website at `/` from the same App Service;
service metadata is at `/api/info`.
Application Insights records each 503 request and its `CHAOS` trace, so request
telemetry, App Service platform metrics and app logs all show the outage. Other
S2 variants can fail only `/api/orders` and leave the root and `/health` available.

Container Apps variant usually shows the same `/api/orders` failure pattern, but correlation evidence comes from revision/deployment events and Container Apps runtime logs.

## 1) Detect

- Confirm the incident trigger (Azure Monitor alert / App Insights 5xx SLO breach).
- Capture first-seen time, impacted endpoint(s), and current 5xx rate.

## 2) Investigate

- Check endpoint health and blast radius:
  - root request and backend action statuses (both return 503 during the chaos outage)
  - `GET /health`
  - `POST /api/orders`
- Review telemetry in App Insights:
  - failed requests (`resultCode startswith "5"`)
  - exceptions (`exceptions`)
  - failing/slow dependencies (`dependencies`)

## 3) Correlate

- Align first-failure time with:
  - recent App Service deployments or slot swaps
  - recent Container Apps revision/deployment changes (when runtime=containerapps)
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

For rg-sre-lab-sbox/orders-api-* only, if the App Service has
`CHAOS_MODE=crash` and `CHAOS_ENABLED=true`, set **only**
`CHAOS_ENABLED=false` on that App Service. The S2 approval hook permits this
specific reversal without approval; other configuration writes and explicit
restarts remain gated. Terraform always deploys `CHAOS_ENABLED=false`, so no
Terraform or workflow change is needed afterwards. Do not use this exception
for a real production app.

If action mode is **Review**, request approval before write actions.

## 6) Verify recovery

- Confirm:
  - `/health` and `/api/orders` recover
  - dependency failures return to baseline
  - 5xx and exception rates drop
  - alert condition clears
- Record root cause, evidence, remediation, and follow-up actions.

## Detailed reference

Use these runtime-specific supplements only as needed:
- `knowledge-base/runbooks/containers/http-500-errors.md` (Container Apps deep-dive commands and queries)
- `knowledge-base/orders-architecture.md` (runtime-neutral incident correlation context)
