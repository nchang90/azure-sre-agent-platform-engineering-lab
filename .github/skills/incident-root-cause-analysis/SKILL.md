---
name: incident-root-cause-analysis
description: Write the root-cause analysis for an AKS incident on the orders platform — a sourced timeline, a numbered 5 Whys from the customer symptom to the missing guardrail, the trigger separated from the underlying cause, and contributing factors. Use after triage has gathered evidence, before the incident update is written. Read-only.
---

# Incident Root-Cause Analysis — Orders Platform (AKS)

You turn the triage evidence into a root-cause analysis (RCA) that an operator
can trust and act on. Scope: the `checkout-api` workload in the `default`
namespace of the S3 AKS cluster (resource group `rg-sre-lab-demo`).

This skill is **read-only**. Never change the cluster, and never state that a
fix was applied unless the evidence shows it.

## Step 1 — Check the evidence first

Use the evidence `aks-triage-agent` already collected. Fill a gap only with a
read-only query; never assert something you have not seen.

| Question | Evidence source |
|---|---|
| Are the pods healthy? | `KubePodInventory`: `PodStatus`, `ContainerStatus`, restart counts |
| Does the Service exist, and what does it select? | `KubeServices`; `kubectl get service checkout-api -n default -o yaml` |
| Does the Service have endpoints? | `kubectl get endpoints checkout-api -n default` |
| What changed, and when? | `KubeEvents` around the first failure; Azure activity log for the cluster |
| Is the app itself failing? | `ContainerLogV2` for `checkout-api` (expect no crash) |
| Is there resource pressure? | `InsightsMetrics` node CPU and memory (expect normal) |

Rule out the other layers before naming the cause: if pods, nodes and the app
are healthy, say so explicitly with the evidence.

## Step 2 — Build the timeline

A UTC table with one row per event, each with its source:

| Time (UTC) | Event | Source |
|---|---|---|
| … | Healthy baseline: Service has endpoints | `KubeServices` / endpoints |
| … | `checkout-api` Service applied with a new selector | `KubeEvents` / activity log |
| … | Endpoints drop to zero; checkout requests start failing | endpoints / alert |
| … | Azure Monitor alert fires | alert history |
| … | ServiceNow incident opened | incident record |

Align the first failure to the nearest change. If you cannot find a change,
say so rather than guessing.

## Step 3 — Write the 5 Whys

Under a heading `### 5 Whys`, write five numbered rungs, each on its own line
and each citing its evidence. Start from what customers saw and stop at the
gap that let it happen:

1. **Why 1:** customers saw checkout timeouts → because requests to the
   `checkout-api` Service reached no pods.
2. **Why 2:** requests reached no pods → because the Service had zero
   endpoints, although the pods were `Running` and `Ready`.
3. **Why 3:** the Service had zero endpoints → because its selector
   (`app: checkout-api-shadow`) no longer matched the pod label
   (`app: checkout-api`).
4. **Why 4:** the selector changed → because a rollout applied a Service
   manifest with the wrong selector.
5. **Why 5 (underlying cause):** the change reached the cluster unnoticed →
   because nothing checks that a Service selector matches its Deployment's pod
   labels before or after deployment.

Use the real values from the evidence; the rungs above show the shape, not the
answer. Then state separately:

- **Trigger:** the change that set it off now (Why 4).
- **Underlying cause:** the missing guardrail that made it possible (Why 5).

## Step 4 — Contributing factors and detection

- **Contributing factors:** what widened the impact or slowed detection, for
  example no readiness signal at the Service level, or an alert that only
  emails people.
- **Why it was hard to spot:** every pod and node looked healthy, so the
  usual dashboards showed green while traffic failed.

## Rules

- Keep it blameless: describe systems and changes, not people.
- Label anything unproven as a hypothesis, with a confidence of `low`,
  `medium` or `high`.
- Keep the root cause out of headings; put it in the body.
- Do not recommend executing a fix. You may name the fix for an operator to
  approve: restore the `app: checkout-api` selector or reapply the healthy
  manifest.

## Output

Return the RCA in this order, ready for `incident-comms-agent` to post and
attach to the incident:

1. What happened — symptom and customer impact
2. Timeline
3. 5 Whys, then trigger and underlying cause
4. Contributing factors and detection
5. What stayed healthy
6. Recommended fix, pending operator approval
