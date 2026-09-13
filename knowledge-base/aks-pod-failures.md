# AKS Pod Failure Investigation Runbook (S3)

Use this runbook for S3 incidents where the `orders-api` deployment in the
`default` namespace is unhealthy, restarting, or unable to schedule.

Follow the lab flow strictly: **detect → triage → correlate → remediate → validate recovery**.

## 1) Detect

- Confirm the triggering signal:
  - `AKS orders-api workload unavailable`
  - `AKS pods not ready`
- Capture the affected pod name, current status, restart count, and first-seen time.

## 2) Triage

- Check the deployment and pods:
  - `kubectl get deployment orders-api -n default`
  - `kubectl get pods -l app=orders-api -n default`
  - `kubectl describe pod <pod-name> -n default`
- Review recent Kubernetes telemetry:
  - `KubePodInventory` for restart counts and latest pod state
  - `KubeEvents` for `BackOff`, `FailedScheduling`, and `Unhealthy`
  - `ContainerLogV2` for crash, image pull, and probe errors

## 3) Correlate

- Correlate the first unhealthy timestamp with:
  - recent AKS rollouts or image changes
  - node pressure or cluster capacity events
  - service or deployment drift from the healthy baseline
- Distinguish fact from hypothesis before choosing a fix.

## 4) Common Failure Patterns

### CrashLoopBackOff or startup failure

- Check previous logs:
  - `kubectl logs <pod-name> -n default --previous`
- Look for `BackOff` or exit-code evidence in `kubectl describe pod`.
- Confirm the deployed image matches the expected healthy baseline.

### ImagePullBackOff

- Check the image reference and pull events:
  - `kubectl describe pod <pod-name> -n default | grep -A6 -E "Image:|Events"`
- Verify the image tag exists and the cluster can pull it.

### Pending or unschedulable pods

- Check scheduling events:
  - `kubectl describe pod <pod-name> -n default | grep -A10 Events`
- Compare requested CPU and memory with node capacity.

### Probe failures or running-but-not-ready

- Inspect readiness and liveness failures in `KubeEvents`.
- Test the workload path if reachable from inside the cluster.

## 5) Remediate (safe and reversible first)

Prefer low-risk rollback and recovery actions:

1. Restore the healthy deployment manifest if a bad image or config was applied.
2. Restart the deployment when the issue looks transient.
3. Scale or repair cluster capacity when scheduling pressure is confirmed.
4. Escalate for image registry or platform issues if the failure is external.

If action mode is **Review**, request approval before write actions.

## 6) Validate Recovery

- Confirm:
  - `kubectl rollout status deployment/orders-api -n default`
  - at least one `orders-api` pod is `Running` and `Ready`
  - restart growth stops
  - the Sev1/Sev2 AKS alert condition clears
- Document the evidence, root cause, mitigation, and follow-up actions in the incident report.
