# AKS Network and Service Connectivity Runbook (S3)

Use this runbook for S3 incidents where `orders-api` is deployed but traffic
cannot reach it inside the AKS cluster.

Follow the lab flow strictly:
**detect → triage → correlate → remediate → validate recovery**.

## 1) Detect

- Confirm the triggering signal:
  - `AKS orders-api service missing`
  - `AKS orders-api workload unavailable`
- Record whether the failure is a missing `Service`, zero endpoints, or
  pod-to-service reachability issue.

## 2) Triage

- Check the `Service` and endpoints:
  - `kubectl get service orders-api -n default`
  - `kubectl get endpoints orders-api -n default`
- Compare selectors to pod labels:
  - `kubectl get service orders-api -n default -o jsonpath='{.spec.selector}'`
  - `kubectl get pods -l app=orders-api -n default --show-labels`
- Inspect cluster events for recent deletes or apply operations affecting
  `orders-api`.

## 3) Correlate

- Correlate the failure with:
  - a recent manifest apply or manual delete
  - selector drift between the `Service` and deployment labels
  - node or CNI issues if the `Service` exists and endpoints are present
- Treat a missing `Service` as confirmed configuration drift, not a transient
  signal.

## 4) Common Failure Patterns

### Missing `orders-api` Service

- `kubectl get service orders-api -n default` returns `NotFound`.
- The Sev1 `AKS orders-api service missing` alert should match this condition.

### Selector mismatch

- The `Service` exists, but `kubectl get endpoints orders-api -n default` is empty.
- Compare `spec.selector` with deployment and pod labels for drift.

### Pod-to-service reachability issue

- The `Service` and endpoints exist, but callers still fail.
- Check AKS events, kube-system health, and any relevant network policy or CNI
  faults.

## 5) Remediate (safe and reversible first)

Prefer low-risk recovery actions:

1. Reapply the healthy `orders-api` manifest if the `Service` or selector
   drifted.
2. Repair the selector or labels if drift is isolated and confirmed.
3. Escalate platform networking issues after confirming the resource
   definitions are healthy.

If action mode is **Review**, request approval before write actions.

## 6) Validate Recovery

- Confirm:
  - `kubectl get service orders-api -n default` succeeds
  - `kubectl get endpoints orders-api -n default` returns backing pod IPs
  - connected workloads can reach the service again
  - the Sev1 service-missing alert clears
- Capture the timeline and exact resource drift in the incident report.
