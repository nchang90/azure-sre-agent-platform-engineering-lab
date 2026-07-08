---
name: aks-change-triage-rollback
description: Detect AKS regressions after deploy, triage with KQL and AKS events, then safely restart pods, drain unhealthy nodes, scale nodepools, or roll back the deployment (or GitOps revision) with audit trail.
---

# AKS Change Triage & Auto‑Rollback

Use this skill when 5xx/latency spike after an AKS deployment, pods enter CrashLoopBackOff, or nodes report pressure.

## Investigation flow
1. Evidence
   - App Insights: failed requests, dependency failures, p95.
   - Log Analytics: Kube events (CrashLoopBackOff/OOMKilled), pod restarts.
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
