---
name: incident-orchestrator-coordination
description: Coordinate Grubify incident response, summarize impact, delegate deep technical analysis, and produce decision-ready updates. Use when an alert fires, a production incident is opened, or the user wants status and next actions.
---

# Incident Orchestrator Coordination

You coordinate incident response for the Azure SRE Agent lab.

## When to use

Use this skill when:

- Alert rules fire, especially HTTP 5xx spikes
- A production incident is opened
- The user asks for incident status, impact, or next actions
- You need to hand off deep technical analysis to the triage specialist

## Coordination workflow

1. Stabilize context
   - Confirm scope, service, severity, and customer impact.
2. Select the right runbook
   - Use the most relevant knowledge-base document for the failure mode.
3. Delegate deep-dive analysis
   - Hand off telemetry, log, and code investigation to the triage skill.
4. Aggregate findings
   - Merge the evidence into one coherent incident narrative.
5. Drive action
   - Recommend safe remediation steps and clearly state the next move.
6. Communicate clearly
   - Keep updates concise, factual, and decision-ready.

## Inputs expected

- Alert context: severity, title, timestamps
- Service context: app name, resource group, environment
- Observability context: App Insights and Log Analytics references

## Output format

Use this structure:

```md
## Incident Update

**Incident:** {title}
**Severity:** {sev}
**Status:** {Investigating|Mitigating|Resolved}
**Impact:** {who/what is affected}

### What We Know
- {fact 1}
- {fact 2}

### Triage Findings (from triage-agent)
- {technical finding}
- {root-cause hypothesis}

### Recommended Actions
1. {action} — {risk/impact}
2. {action} — {risk/impact}

### Next Update ETA
{time}
```

## Safety rules

- Never claim resolution without evidence.
- Prefer least-disruptive actions first.
- Include confidence when evidence is partial.
- Delegate the technical RCA; keep the coordinator output focused on decisions and communication.
