---
name: aks-change-triage-rollback
description: Detect AKS regressions after deploy, triage with KQL and AKS events, then safely restart pods, drain unhealthy nodes, scale nodepools, or roll back the deployment (or GitOps revision) with audit trail.
---

# AKS Change Triage & Auto‑Rollback

Use this skill when 5xx/latency spike after an AKS deployment, pods enter CrashLoopBackOff, or nodes report pressure.

## Investigation flow
1. Evidence
   - App Insights: failed requests, dependency failures, p95.
   - Log Analytics: Kube events (CrashLoopBackOff/OOMKilled), pod restarts, container logs.
   - AKS describe: deployment and replicaset state.
   - GitOps metadata (if present): last commit/PR.
2. Regression check
   - Compare error/latency deltas vs previous 15–30m baseline.
   - Correlate with recent rollout or HPA changes.
3. Remediation (least‑risk first)
   - Restart pods: `kubectl rollout restart deployment <svc>`.
   - Drain node if pressure: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`.
   - Scale if load: `az aks nodepool scale ...`.
   - Roll back if regression persists: `kubectl rollout undo ...` or GitOps revert.

## AKS Log Analytics queries

Use AKS/Kubernetes tables for S3. Do not use Container Apps tables for AKS incidents.

### Pod failures and restarts
```kql
KubePodInventory
| where TimeGenerated > ago(1h)
| where Namespace !in ("kube-system", "gatekeeper-system", "calico-system")
| where PodStatus !in ("Running", "Succeeded") or ContainerRestartCount > 0
| summarize
    Restarts = max(ContainerRestartCount),
    LastStatus = arg_max(TimeGenerated, PodStatus, ContainerStatusReason)
  by ClusterName, Namespace, ControllerName, PodName, ContainerName
| order by Restarts desc, PodName asc
```

### CrashLoopBackOff, OOMKilled, and scheduling events
```kql
KubeEvents
| where TimeGenerated > ago(1h)
| where Reason in ("BackOff", "Failed", "FailedScheduling", "OOMKilled", "Unhealthy")
    or Message has_any ("CrashLoopBackOff", "OOMKilled", "Readiness probe failed", "Liveness probe failed")
| project TimeGenerated, ClusterName, Namespace, ObjectKind, Name, Reason, Message
| order by TimeGenerated desc
```

### Container logs with V2 and legacy fallback
```kql
union isfuzzy=true
    (ContainerLogV2
    | where TimeGenerated > ago(1h)
    | project TimeGenerated, Source = "ContainerLogV2", PodName, ContainerName, Namespace, LogMessage),
    (ContainerLog
    | where TimeGenerated > ago(1h)
    | project TimeGenerated, Source = "ContainerLog", PodName = Name, ContainerName = ContainerID, Namespace = "", LogMessage = LogEntry)
| where LogMessage has_any ("error", "exception", "failed", "CrashLoopBackOff", "OOMKilled", "timeout")
| summarize Count = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated)
  by Source, Namespace, PodName, ContainerName, LogMessage
| order by Count desc
| take 25
```

### Node pressure and saturation
```kql
InsightsMetrics
| where TimeGenerated > ago(1h)
| where Namespace in ("container.azm.ms/disk", "container.azm.ms/memory", "container.azm.ms/cpu")
| summarize AvgValue = avg(Val), MaxValue = max(Val) by Computer, Namespace, Name, bin(TimeGenerated, 5m)
| order by TimeGenerated desc, MaxValue desc
```

## Safety rules
- Require approval for rollback when action_mode == Review.
- Limit scope to target namespace/service; never wildcard cluster‑wide.
- One remediation at a time; re‑measure before proceeding.
- Always capture commands, stdout/stderr, and links to KQL in the incident timeline.

## Output format
Return a concise report:
```
## AKS Remediation Report
Evidence: {summary with key KQL and events}
Decision: {restart|drain|scale|rollback} — rationale
Actions Taken: [ordered list]
Post‑state: {error rate, p95, restarts}
Confidence: {High|Medium|Low}
Follow‑ups: [readiness/liveness, retry caps, alerts]
```
