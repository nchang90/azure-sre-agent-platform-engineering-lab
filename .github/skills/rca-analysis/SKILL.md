---
name: rca-analysis
description: Produce the evidence-backed root-cause narrative for an orders-platform incident on App Service, Container Apps or AKS — a sourced UTC timeline, an explicit 5-Whys ladder, and the trigger separated from the latent cause. Use once triage has gathered evidence and before the incident summary, operator update or post-incident report is written.
---

# Root Cause Analysis — Orders Platform

You produce the analytical core of an incident record: a defensible root-cause
narrative that downstream summary, communications and reporting steps can use
without adding claims of their own.

Scope: the checkout/orders workload, whichever runtime it is deployed on —
`orders-api` on App Service or Container Apps, `checkout-api` on AKS. Resource group `rg-sre-lab-{environment}`.

## Authoritative external references

Use these as primary references before relying on other external sources:

1. Azure SRE Agent docs: https://sre.azure.com/docs
2. Official Azure SRE Agent repo/resources: https://github.com/microsoft/sre-agent

## When to use

- Triage has collected evidence and a root-cause narrative is needed.
- An incident is mitigated or still open, and the record needs a diagnosis
  rather than a raw evidence dump.
- An operator asks "why did this happen" or "what actually broke".

## Step 1 — Identify the runtime

The runtime decides your evidence sources. Confirm it before querying — do not
assume from the alert name.

| Runtime | Confirm with | Primary telemetry |
|---------|--------------|-------------------|
| App Service | `az webapp show` via `RunAzCliReadCommands` | App Insights `requests`, `exceptions`, `dependencies` |
| Container Apps | `az containerapp show` via `RunAzCliReadCommands` | App Insights + `ContainerAppConsoleLogs_CL`, `ContainerAppSystemLogs_CL` |
| AKS | `az aks show` via `RunAzCliReadCommands` | `KubePodInventory`, `KubeServices`, `KubeEvents`, `ContainerLogV2`, `InsightsMetrics` |

## Gather evidence first (never assert without it)

Retrieve `incident-report.md` and `orders-architecture.md` with `SearchMemory`
first; the report structure below must match the stored template.

Reconstruct the timeline from evidence, not from narrative memory. Every row
cites the query or command that produced it.

### All runtimes

| Need | Source |
|------|--------|
| Caller-visible failures, latency, exceptions | `QueryAppInsightsByResourceId` |
| Dependency failures and their target | `QueryAppInsightsByResourceId` (`dependencies`) |
| Subscription-level change and operation history | `RunAzCliReadCommands` — `az monitor activity-log list --start-time ... --end-time ...` |
| Workload configuration as it stands now | `RunAzCliReadCommands` (read-only calls; use `GetAzCliHelp` for syntax) |

### App Service and Container Apps

| Need | Source |
|------|--------|
| Deployment history and timing | `az webapp log deployment list` / `az containerapp revision list --query "[].{rev:name,created:properties.createdTime,active:properties.active}"` |
| Configuration drift (settings, connection strings) | `az webapp config appsettings list` / `az containerapp show --query properties.template` |
| Slot state and swap history | `az webapp deployment slot list`, plus the activity log for the swap operation |
| Platform-level health vs application health | `az webapp show --query state` — a `Running` app with failing requests is an application fault, not a platform one |

### AKS

| Need | Source |
|------|--------|
| Pod state, readiness, restart counts | `KubePodInventory` via `QueryLogAnalyticsByWorkspaceId` |
| Service and endpoint state | `KubeServices` via `QueryLogAnalyticsByWorkspaceId` |
| Apply / rollout / scheduling events | `KubeEvents` via `QueryLogAnalyticsByWorkspaceId` |
| Application-level failure confirmation | `ContainerLogV2` via `QueryLogAnalyticsByWorkspaceId` |
| Node and pod resource pressure | `InsightsMetrics` via `QueryLogAnalyticsByWorkspaceId` |

## Correlate the onset with a change (do this explicitly)

Align first-failure time to the nearest deployment, revision, manifest apply or
configuration change. This is the step that turns a symptom report into an RCA.

1. Establish **first-failure time** from telemetry — the first 5xx or first
   failed dependency, not the alert fire time. The alert lags the fault.
2. List changes in a window bracketing that time (at least 30 minutes either
   side) from deployment history and the activity log.
3. State the gap explicitly: "first failure at `{ts}`, `{change}` completed at
   `{ts}`, delta `{n}` minutes".
4. If the incident payload or the failure response carries a **change-request
   id** (the orders-api forced-failure detail carries one, e.g. `CHG0030001`),
   extract it and reconcile it against the deployment history — a CR id that
   matches an active change window is direct evidence, not a coincidence.
5. If no change correlates, say so explicitly rather than inventing one. An
   uncorrelated onset is itself a finding (external dependency, data-driven
   trigger, or gradual saturation).

### Discriminating between application regression classes

When the runtime is healthy but the application is failing, name the class and
say what evidence separates it from its neighbours.

| Class | Discriminating evidence |
|-------|-------------------------|
| Bad configuration / app settings | Exception type is config or auth related; `appsettings` differ from last-known-good; no code change in the window |
| Database or connection-string regression | `dependencies` show failures against the data target; exception is a connection or timeout type; app-level handlers never run |
| Dependency timeout | `dependencies` show rising duration before failures; failures cascade from one target outward |
| Code regression | Exceptions concentrate in one operation; other endpoints unaffected; correlates to a specific deployment |
| Slot configuration drift | Failure starts exactly at a swap operation; production settings differ from the slot that was promoted |

Say which class the evidence supports **and** which you ruled out, with the
query that ruled it out.

## The 5-Whys ladder (mandatory)

Write an explicit, numbered ladder — not a one-line summary. Start at the
customer-visible symptom and ask "why?" until you reach the condition that made
the failure possible. Each rung cites its evidence.

```text
Why 1: callers saw <symptom>           -> because <immediate technical effect>
Why 2: <effect>                        -> because <misbehaving component or config>
Why 3: <component> misbehaved          -> because <the change or state that caused it>
Why 4: that change happened            -> because <how it was introduced>
Why 5: it went undetected/was possible -> because <missing guardrail or gap>
```

### Worked example — App Service backend regression

```text
Why 1: the dashboard loaded but checkout actions failed
       -> because POST /api/orders returned HTTP 500
          (App Insights requests: 5xx on that operation only)
Why 2: only /api/orders returned 500
       -> because that request path failed inside the application
          (exceptions on the operation; /health and static paths unaffected)
Why 3: the application failed on that path
       -> because <config / dependency / code regression class from the table above>
          (dependencies + appsettings evidence)
Why 4: that state reached production
       -> because it shipped in the deployment at <ts>, <n> minutes before first
          failure (deployment history + activity log)
Why 5: it reached production undetected
       -> because the health probe only covers /health, which does not exercise
          the failing path, so the rollout gate passed
```

Note the shape: the platform stayed `Running`, CPU and memory stayed at
baseline, and `/health` kept passing throughout. Record that — the healthy half
of the picture is what makes the diagnosis credible and is what distinguishes an
application regression from a platform fault.

### Worked example — AKS selector drift

```text
Why 1: checkout requests failed or timed out
       -> because callers reaching the checkout-api Service got no backend
          (App Insights failed requests, no corresponding server-side traces)
Why 2: the Service returned no backend
       -> because it selected zero endpoints (KubeServices; endpoints list empty)
Why 3: the Service selected zero endpoints
       -> because its selector no longer matched any healthy pod labels
          (KubePodInventory shows Running/Ready pods with the prior labels)
Why 4: the selector stopped matching
       -> because the most recent apply changed the Service selector
          (KubeEvents apply entry at <ts>)
Why 5: the mismatch reached production undetected
       -> because no endpoint-count check gates the rollout and the readiness
          signal only covers pods, not routing
```

Then state the two separately:

- **Trigger** — what set it off now (the specific deployment, apply or swap).
- **Latent cause** — the condition that allowed it (Why 5: the missing guardrail).

In both examples the trigger is mundane and the latent cause is the real
finding. Do not let the ladder collapse into "a bad change was deployed".

## Presentation rules

- Headings state the symptom; the cause appears in the body, never in a title.
- Render the ladder under a literal `### 5 Whys` heading, five numbered rungs,
  each on its own line. A diagram may accompany it but never replaces it.
- Label every statement **confirmed** (has evidence), **likely** (inferred from
  partial evidence), or **suspected** (hypothesis). Never blur the three.
- Blameless: describe systems, changes and gaps, not individuals.
- State what stayed healthy as well as what broke.
- If the after-window is too short to claim recovery, say so.

## Remediation stance

This skill analyses; it does not decide or perform remediation.

- Never claim an action was executed unless you have evidence it completed.
  Verify recovery from telemetry, not from the fact that a command was issued.
- Where the agent is running in **Review** mode or in a read-only investigation
  chain, phrase every action as an operator next step requiring approval, and do
  not call write tools.
- Where the agent is running in **Autonomous** mode, remediation is owned by the
  triage or remediation step, not by this skill. Supply the root cause and the
  ranked next steps; let that step act and report back what it verified.

## Output format

Emit the report below. It fills the **Timeline**, **Root Cause** and
**Follow-up Actions** sections of `incident-report.md`.

## Root Cause Analysis

**Incident:** `{INC id or alert name}`
**Service:** `{orders-api | checkout-api}`
**Runtime:** `{App Service | Container Apps | AKS}`
**Status:** `{Investigating | Mitigated | Resolved}`

### What happened

One or two sentences, customer-visible symptom only.

### What stayed healthy

`{e.g. platform state Running, /health passing, CPU and memory at baseline — with the query that shows it}`

### Timeline (UTC)

| Time | Event | Evidence |
|------|-------|----------|
| `{ts}` | First failure observed | `{query}` |
| `{ts}` | `{change correlated}` | `{deployment history / activity log}` |
| `{ts}` | Alert fired | `{alert rule}` |
| `{ts}` | `{mitigation}` | `{evidence it completed}` |

### Change correlation

First failure `{ts}` · nearest change `{change}` at `{ts}` · delta `{n}` minutes
Change-request id in payload: `{id or "none"}` — `{reconciled | unreconciled}`

### Regression class

`{class}` — ruled out `{classes}` because `{evidence}`

### 5 Whys

Why 1: `{symptom}` -> because `{effect}` — `{evidence}`
Why 2: `{effect}` -> because `{component}` — `{evidence}`
Why 3: `{component}` -> because `{change or state}` — `{evidence}`
Why 4: `{change}` -> because `{how introduced}` — `{evidence}`
Why 5: `{undetected}` -> because `{missing guardrail}` — `{evidence}`

**Trigger:** `{what set it off now}`
**Latent cause:** `{the condition that made it possible}`

### Contributing factors

- `{detection, guardrail or process gap that widened impact}`

### Confidence

`{low | medium | high}` — `{what would raise it}`

### Recommended next steps

| Action | Type | Rationale |
|--------|------|-----------|
| `{action}` | `{Corrective \| Preventive \| Detective}` | `{why}` |
