---
name: evidence-before-after
description: Build the before/after evidence for an AKS incident on the orders platform — classify the fault first, then produce a state delta table and path diagram for routing or configuration faults, or a windowed time-series comparison for performance and availability faults. Use when an incident record needs proof of what changed, not a chart by reflex.
---

# Before / After Evidence — Orders Platform (AKS)

You prove what changed during an incident using the *right* evidence for the
fault class. A smooth metric plotted for a binary routing fault is misleading
and adds no insight — the decision in Step 1 is the point of this skill.

Scope: the `checkout-api` workload in the `default` namespace of the S3 AKS
cluster (resource group `rg-sre-lab-demo`). This skill is **read-only**.

## Authoritative external references

Use these as primary references before relying on other external sources:

1. Azure SRE Agent docs: https://sre.azure.com/docs
2. Official Azure SRE Agent repo/resources: https://github.com/microsoft/sre-agent

## When to use

- An incident record or operator update needs evidence of impact and scope.
- `rca-analysis` has confirmed a root cause and fixed the time windows.
- Someone asks "show me what actually changed" or "prove the pods were fine".

## Step 1 — Choose the evidence form FIRST (do not skip)

Classify what changed, then pick the form that explains *that*.

| Fault class | What changed | Primary evidence | Secondary (only if telemetry supports it) |
|---|---|---|---|
| **Routing / selector / config / RBAC** | a path was **open -> closed** (binary) | **state delta table + before/after path diagram** | one short recovery curve |
| **Performance / latency / saturation** | a metric **degraded -> recovered** (gradual) | **time-series across three windows + percentile delta table** | before-vs-after summary bars |
| **Availability / crash / restart loops** | error or restart rate **rose -> fell** | **time-series + delta table** | summary bars |

The S3 selector-drift variant is the first row. Pods stay `Running` and `Ready`
and node CPU and memory stay flat — so a CPU or pod-count chart shows a straight
line and proves nothing. Lead with the state delta.

If a fault has both a binary cause and a metric symptom, lead with the delta
table and diagram that explain the cause, and use **one** metric chart only as
supporting proof of caller impact.

## Step 2 — Capture the before/after state (routing and config faults)

Read the current state, then reconstruct the prior state from the change history
and the windows confirmed by `rca-analysis`.

- Service and endpoint state from `KubeServices` via
  `QueryLogAnalyticsByWorkspaceId`; the endpoint count is the headline number.
- Pod labels and readiness from `KubePodInventory` — this is what shows the
  healthy half of the picture.
- The change itself from `KubeEvents` (apply, rollout, scheduling entries).
- Cluster and workload configuration from `RunAzCliReadCommands` (read-only).

Build a **state delta table** — `item · before · after · effect`:

| Item | Before | After | Effect |
|------|--------|-------|--------|
| `checkout-api` Service endpoints | `3` | `0` | callers reach no backend |
| `checkout-api` Service selector | `app=checkout-api` | `app=checkout-api-v2` | selector matches no pod |
| `checkout-api` pod labels | `app=checkout-api` | `app=checkout-api` | unchanged — pods are not the fault |
| Pod readiness | `3/3 Ready` | `3/3 Ready` | workload healthy throughout |
| `POST /api/orders` | `200` | `timeout / 5xx` | customer-visible failure |

Then render a **before -> after path diagram** showing the broken hop. ASCII is
preferred — it survives into ServiceNow work notes and chat, where an image does
not:

```text
BEFORE (routing intact)                  DURING (routing broken)
caller -> Service checkout-api             caller -> Service checkout-api
             |  selector matches                      |  selector matches nothing
             v                                        x
        [3 Ready pods]                           [3 Ready pods]  <- still healthy
endpoints: 3        status: 200          endpoints: 0        status: timeout / 5xx
```

Use `ExecutePythonCode` for a rendered image only when the report needs one; the
ASCII form is the default and must always be present.

## Step 3 — Pull metrics (performance and availability faults, or impact proof)

Only when a metric genuinely tells the story. Define three windows using the
exact boundaries from `rca-analysis`:

- **Before** — healthy baseline.
- **During** — detection to mitigation.
- **After** — post-change, long enough to be credible.

Per window pull the metric matching the symptom: caller-visible failure rate and
latency percentiles from `QueryAppInsightsByResourceId`; restart counts and pod
state from `KubePodInventory`; node and pod resource pressure from
`InsightsMetrics`. Report p50/p95/p99 rather than averages.

When charting with `ExecutePythonCode`: same units, axes and aggregation across
windows, every series labelled, and the detection and change points annotated.

## Safety rules

- Read-only. Never run `RunAzCliWriteCommands` and never apply a manifest.
- Never plot a metric that does not change shape across the fault, and never
  fabricate a trend to fill a slide.
- Never claim recovery a number does not support; if the after-window is too
  short, label the row `insufficient data`.
- Reconstructed "before" values are labelled as reconstructed, with their source.

## Output format

## Before / After Evidence

**Fault class:** `{routing-config | performance | availability}`
**Evidence form chosen:** `{state delta + path diagram | time-series + delta table}`
**Why:** one sentence on what changed and why this form shows it.

**Windows (UTC):** Before `{range}` · During `{range}` · After `{range}`

### State delta

| Item | Before | After | Effect |
|------|--------|-------|--------|
| `{item}` | `{value}` | `{value}` | `{effect}` |

### Path

```text
{before -> after ASCII diagram}
```

### Caller impact

| Metric | Before | During | After | Source |
|--------|--------|--------|-------|--------|
| `{metric}` | `{v}` | `{v}` | `{v}` | `{query}` |

### Evidence gaps

- `{anything the telemetry could not confirm}`
