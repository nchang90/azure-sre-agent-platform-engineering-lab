# Orders API HTTP 500 Incident Playbook (S2)

Use this runbook for S2 incidents where `orders-api` returns elevated HTTP 500s.
Follow the lab flow strictly: **detect → triage → correlate → remediate → validate recovery**.

## 1) Detect

- Confirm the triggering signal (Azure Monitor alert, incident event, or 5xx SLO breach).
- Verify affected endpoint(s), current 5xx rate, and first-seen timestamp.

## 2) Triage

- Check Orders API health:
  - `GET /health`
- Review recent telemetry:
  - Application Insights failed requests (`resultCode startswith "5"`)
  - Log Analytics (`ContainerAppConsoleLogs_CL`, `AppTraces`, `ContainerAppSystemLogs_CL`)
- Determine blast radius (all users vs partial impact, single endpoint vs broad failure).

## 3) Correlate

- Correlate failure start time with:
  - recent Container Apps revision/deployment changes
  - active change request context from `change-lookup`
  - dependency failures/timeouts (DB/API/external services)
- Distinguish fact vs hypothesis before selecting remediation.

## 4) Remediate (safe and reversible first)

Prefer low-risk rollback and recovery actions:

1. Roll back to last healthy revision if errors started after deployment.
2. Restart affected revision/pods if transient platform/runtime fault is suspected.
3. Scale out when CPU/memory saturation causes timeout-driven 500s.
4. Fix configuration/secret/dependency connectivity issues if confirmed.

If action mode is **Review**, request approval before write actions.

## 5) Validate Recovery

- Confirm:
  - `GET /health` returns healthy
  - 5xx rate returns to baseline
  - error logs/exceptions stabilize
  - alert condition clears
- Document timeline, confirmed root cause, mitigation, and follow-up actions in the incident report.

## Detailed Reference

For expanded KQL/CLI procedures, see:
- `knowledge-base/runbooks/containers/http-500-errors.md`
