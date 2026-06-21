---
name: containerapps-latency-diagnostics
description: Diagnose high latency, P99 degradation, and timeout incidents in Azure Container Apps. Use when response times spike, P99/P95 breaches an SLO threshold, requests time out, or downstream dependency slowness is suspected.
---

# Container Apps Latency Diagnostics

You diagnose high latency, P99 degradation, and timeout incidents in the orders-api Container Apps stack using telemetry, dependency traces, and resource signals.

## Authoritative external references

Use these as primary references before relying on other external sources:

1. Azure SRE Agent docs: https://sre.azure.com/docs
2. Official Azure SRE Agent repo/resources: https://github.com/microsoft/sre-agent

## When to use

Use this skill when:

- P99 or P95 response time breaches the SLO threshold (default: P99 > 2s for orders-api)
- Requests are timing out (HTTP 408, 504, or client-side timeout errors)
- End-to-end latency is elevated but error rate is not yet spiking (leading indicator)
- A downstream dependency (SQL, CosmosDB, Service Bus, external API) is slow
- A recent deployment, revision change, or scaling event coincides with latency increase

## Investigation flow

1. Confirm the latency pattern
   - Identify affected endpoint(s), percentile (P50/P95/P99), timeframe, and whether all replicas are affected or only a subset.
2. Check if latency is client-side or server-side
   - Compare App Insights request duration vs. dependency duration to isolate where time is spent.
3. Inspect dependency traces
   - Query App Insights for slow or failed dependencies: SQL, CosmosDB, Service Bus, HTTP calls to downstream services.
   - Flag any dependency with duration > 1s or failure rate > 1%.
4. Check resource pressure
   - Review CPU throttling, memory pressure, thread pool exhaustion, and replica count vs. request volume.
5. Correlate with platform events
   - Check for revision restarts, cold starts (new replica spin-up), ingress rule changes, and scaling events near the latency spike onset.
6. Correlate with recent changes
   - Cross-reference the latency onset timestamp with recent deployments, CR activity, and config changes.
7. Recommend safe remediation
   - Prefer reversible mitigations: scale out, connection pool tuning, circuit breaker toggle, or rollback before invasive changes.

## KQL reference queries

### P99 latency over time (App Insights)
```kql
requests
| where timestamp > ago(1h)
| summarize percentile(duration, 99), percentile(duration, 95), percentile(duration, 50) by bin(timestamp, 5m)
| render timechart
```

### Slow dependencies (App Insights)
```kql
dependencies
| where timestamp > ago(1h)
| where duration > 1000
| summarize count(), avg(duration), max(duration) by name, type, target
| order by avg_duration desc
```

### Timeout errors by endpoint (App Insights)
```kql
requests
| where timestamp > ago(1h)
| where resultCode in ("408", "504") or success == false
| summarize count() by name, resultCode, bin(timestamp, 5m)
| order by timestamp desc
```

### Replica CPU/memory pressure (Log Analytics)
```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "timeout" or Log_s contains "slow" or Log_s contains "connection pool"
| project TimeGenerated, ContainerAppName_s, RevisionName_s, Log_s
| order by TimeGenerated desc
```

## Common evidence sources

- `knowledge-base/orders-architecture.md`
- App Insights requests and dependencies tables
- Container App metrics: RequestLatency, CpuUsageNanoCores, MemoryWorkingSetBytes
- Revision restart and scaling event logs

## Latency budget reference (orders-api)

| Endpoint | P50 target | P99 SLO threshold |
|---|---|---|
| `POST /api/orders` | < 300ms | < 2s |
| `GET /api/orders` | < 150ms | < 1s |
| `GET /health` | < 50ms | < 500ms |

Flag any endpoint exceeding its P99 SLO threshold as a confirmed S2 signal.

## Remediation decision tree

```
Latency spike detected
├── Dependency slow (SQL/CosmosDB/Service Bus > 1s)?
│   ├── Yes → investigate dependency health, check connection pool, consider circuit breaker
│   └── No → continue
├── CPU throttling or memory pressure on replicas?
│   ├── Yes → scale out (approved safe action)
│   └── No → continue
├── Cold starts on new replicas?
│   ├── Yes → increase min-replicas to avoid scale-to-zero
│   └── No → continue
├── Latency onset matches recent deployment?
│   ├── Yes → recommend revision rollback (human approval required)
│   └── No → escalate with full evidence bundle
```

## Safety rules

- Do not perform destructive actions without approval.
- Distinguish evidence from assumptions — label any latency cause as "confirmed", "likely", or "suspected".
- Prefer scale-out and config changes over rollback unless a deployment correlation is confirmed.
- Document unknowns explicitly when the evidence is incomplete.

## Output format

```md
## Latency Triage Report

**Service:** {container-app-name}
**Time Window:** {start} - {end}
**Severity:** {High|Medium|Low}
**SLO Breach:** {Yes — P99 {value}ms > {threshold}ms | No}

### Evidence Summary
- Affected endpoints: {list}
- P99 / P95 / P50: {values}
- Timeout count: {count}
- Primary bottleneck: {client | server | dependency | resource pressure}

### Dependency Analysis
- Slow dependencies: {name, avg duration, failure rate}
- Healthy dependencies: {list}

### Root Cause Analysis
{most likely cause with evidence}

### Code / Config Correlation
- {file or config key}:{line or value} — {why relevant}

### Recommended Actions
1. Immediate mitigation: {action}
2. Short-term fix: {action}
3. Long-term prevention: {action}

### Confidence
{High|Medium|Low} — {reason}
```