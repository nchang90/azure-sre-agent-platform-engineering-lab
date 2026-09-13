# AKS Resource Exhaustion Runbook (S3)

Use this runbook for S3 incidents where `orders-api` or its AKS nodes show CPU,
memory, or scheduling pressure.

Follow the lab flow strictly:
**detect → triage → correlate → remediate → validate recovery**.

## 1) Detect

- Confirm the triggering signal:
  - `AKS pods not ready`
  - node pressure, pending pods, or repeated restarts during investigation
- Record the affected pod or node, peak pressure symptom, and first-seen time.

## 2) Triage

- Check current usage:
  - `kubectl top pods -n default`
  - `kubectl top nodes`
- Inspect scheduling or pressure events:
  - `kubectl describe pod <pod-name> -n default`
  - `kubectl describe node <node-name>`
- Review telemetry:
  - `InsightsMetrics` for CPU and memory saturation
  - `KubeNodeInventory` for node health
  - `KubePodInventory` for restart spikes or unschedulable pods

## 3) Correlate

- Correlate pressure with:
  - a recent rollout or configuration change
  - a noisy neighbor or unexpected workload on the cluster
  - undersized requests and limits on `orders-api`
- Separate cluster-wide saturation from a single failing deployment.

## 4) Common Failure Patterns

### CPU saturation

- Pods remain running but latency or readiness degrades.
- Check whether one node or one workload is consuming a disproportionate share
  of CPU.

### Memory pressure or OOMKilled

- Pods restart and `kubectl describe pod` shows `OOMKilled`.
- Check whether the node also reports `MemoryPressure`.

### Scheduling failures

- Pods remain `Pending` with `FailedScheduling` events.
- Compare `orders-api` resource requests against current allocatable node capacity.

### Unhealthy nodes

- Nodes show `NotReady`, `DiskPressure`, `MemoryPressure`, or `PIDPressure`.
- Validate whether draining or scaling the node pool is safer than repeated pod
  restarts.

## 5) Remediate (safe and reversible first)

Prefer low-risk recovery actions:

1. Remove or roll back the workload change that introduced excess demand.
2. Restart the affected deployment only after pressure is understood.
3. Drain or replace unhealthy nodes when node-level issues are isolated.
4. Scale the node pool when sustained cluster capacity shortfall is confirmed.

If action mode is **Review**, request approval before write actions.

## 6) Validate Recovery

- Confirm:
  - `orders-api` pods schedule successfully and remain ready
  - node pressure clears
  - CPU and memory metrics trend back toward baseline
  - alert conditions stop firing
- Capture the before/after evidence and any capacity follow-up in the incident report.
