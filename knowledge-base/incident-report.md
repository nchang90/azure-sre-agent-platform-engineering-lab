# Incident Report — Orders Platform

Use this template to produce the post-incident report after an investigation or
remediation completes. The diagnostics skills (`containerapps-500-diagnostics`,
`containerapps-latency-diagnostics`) emit a triage report during the incident;
this document is the durable record written once the incident is resolved.

---

## Header

| Field | Value |
|-------|-------|
| Incident ID | `INC-{number}` |
| Service | `{container-app-name}` |
| Severity | `{Sev1 \| Sev2 \| Sev3}` |
| Status | `{Investigating \| Mitigated \| Resolved}` |
| Detected | `{UTC timestamp}` |
| Resolved | `{UTC timestamp}` |
| Duration | `{minutes}` |
| Action mode | `{Review \| Automatic}` |

---

## Summary

One or two sentences: what failed, who was impacted, and how it was resolved.

## Impact

- Affected endpoints: `{list}`
- Error / latency signal: `{e.g. 45% 5xx rate, P99 4.2s}`
- Affected users / sessions: `{count}`
- Customer-visible duration: `{minutes}`

## Timeline (UTC)

| Time | Event |
|------|-------|
| `{ts}` | Alert fired / first signal |
| `{ts}` | Investigation started |
| `{ts}` | Root cause identified |
| `{ts}` | Mitigation applied |
| `{ts}` | Service recovered |

## Root Cause

State the confirmed cause with supporting evidence. Distinguish **confirmed**
from **likely** from **suspected**. Reference the KQL queries or metrics used.

## Remediation

- Immediate mitigation: `{action taken — e.g. revision rollback, scale-out}`
- Approval: `{auto-approved (High/Automatic) \| human-approved by {who}}`
- Verification: `{how recovery was confirmed}`

## Follow-up Actions

| Action | Owner | Type | Status |
|--------|-------|------|--------|
| `{e.g. add memory limit alert}` | `{team}` | Preventive | Open |
| `{e.g. fix N+1 query in OrderService}` | `{team}` | Corrective | Open |

## Links

- Alert / incident: `{portal or connector link}`
- Log Analytics query: `{link}`
- GitHub issue: `{link}`
- Related change request: `{link}`
