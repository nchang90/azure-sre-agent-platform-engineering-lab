---
name: containerapps-500-diagnostics
description: Diagnose HTTP 5xx incidents in the Container Apps stack using telemetry, logs, and code correlation. Use when the API returns 500/503 errors, requests fail after a deployment, or a memory leak/OOM pattern is suspected.
---

# Container Apps 5xx Diagnostics

You diagnose HTTP 5xx incidents in the Container Apps stack using logs, metrics, and code correlation.

## Authoritative external references

Use these as primary references before relying on other external sources:

1. Azure SRE Agent docs: https://sre.azure.com/docs
2. Official Azure SRE Agent repo/resources: https://github.com/microsoft/sre-agent

When you need specifics, prioritize linked pages from these sources relevant to the task (for example, Incident Response, Root Cause Analysis, Connectors, and labs).

## When to use

Use this skill when:

- HTTP 5xx alerts fire for the backend Container App
- Users report cart, checkout, or order failures
- The API becomes slow, unstable, or starts returning 500/503 responses
- A deployment, revision change, or memory-pressure event needs root-cause analysis

## Investigation flow

1. Confirm the error pattern
   - Identify affected endpoint(s), timeframe, and failure rate.
2. Check resource pressure first
   - Review CPU, memory, request volume, and restart count.
3. Correlate logs and telemetry
   - Query Log Analytics and Application Insights for exceptions, failed dependencies, and traces.
4. Inspect platform signals
   - Check revision health, restarts, scaling behavior, ingress changes, and recent deployments.
5. Map findings back to code
   - Connect stack traces or error messages to likely controllers, routes, or service methods.
6. Recommend safe remediation
   - Prefer reversible mitigations such as rollback, scale-out, or config fixes before invasive changes.

## Common evidence sources

- `knowledge-base/http-500-errors.md`
- `knowledge-base/orders-architecture.md`
- `knowledge-base/incident-report.md`
- `https://sre.azure.com/docs`
- `https://github.com/microsoft/sre-agent`
- Container App logs and revision history
- App Insights requests, dependencies, and exceptions

## Reference usage order

1. Local runbooks and knowledge files in this repository.
2. Azure SRE Agent official docs (`sre.azure.com/docs`) for product behavior and capabilities.
3. Official `microsoft/sre-agent` repository for labs, examples, and implementation patterns.
4. Any other source only when the above do not provide the needed detail.

## Output format

Use this structure:

```md
## 5xx Triage Report

**Service:** {container-app-name}
**Time Window:** {start} - {end}
**Severity:** {High|Medium|Low}

### Evidence Summary
- Requests failed: {count/rate}
- Primary endpoints: {list}
- Exception signature(s): {list}

### Root Cause Analysis
{most likely cause with evidence}

### Code Correlation
- {file}:{line} — {why relevant}
- {file}:{line} — {why relevant}

### Recommended Actions
1. Immediate mitigation: {action}
2. Short-term fix: {action}
3. Long-term prevention: {action}

### Confidence
{High|Medium|Low} — {reason}
```

## Safety rules

- Do not perform destructive actions without approval.
- Distinguish evidence from assumptions.
- Prefer the least disruptive fix that addresses the symptom.
- Document unknowns explicitly when the evidence is incomplete.
