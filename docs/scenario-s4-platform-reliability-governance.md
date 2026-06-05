# S4 - Platform Reliability Governance

Persona: Platform Engineering

## Story

After incident triage and remediation, the platform team runs a governance pass to prevent recurrence. The agent evaluates core reliability guardrails, scores risk, and turns gaps into concrete backlog work for platform and service teams. Because the agent has memory from S1–S3, it can correlate guardrail failures directly to the incident that just happened.

## Azure SRE Agent Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Memory and learning** | Agent recalls the S1/S2 incident, the rogue revision, and the missing CR — it references these as evidence against specific guardrails |
| **Deep context** | Agent reads the connected code repository to check for missing probe configuration, resource limits, and test coverage |
| **`ExecutePythonCode`** | Agent generates a risk score chart and governance summary table using the Python tool |
| **Knowledge base** | `platform-reliability-governance.md` defines the guardrail checklist and scoring model; `change-risk-assessment.md` informs the risk dimension scores |
| **GitHub issue creation** | For each Warn or Fail guardrail, the agent creates a GitHub backlog issue with owner, due date, and acceptance criteria |
| **Proactive mode** | Unlike S1–S3 which are reactive (alert or schedule driven), S4 is initiated by the platform team asking *"run a governance review"* |

## Scenario Dependencies

- **Requires:** Run S1 or S2 first — the agent needs incident memory to correlate guardrail failures to real evidence
- **Recommended:** Run S3 before S4 so the agent also has issue-triage context (policy-violation issues map directly to the CR-linkage guardrail)
- **Completes the loop:** S4 creates the backlog items that prevent S1 from happening again

## Guardrails Evaluated

| # | Guardrail | Maps to S1–S3 evidence |
|---|-----------|------------------------|
| 1 | Every production deploy has a linked and active change request | S1: `change-lookup` found no active CR; S3: policy-violation issue filed |
| 2 | Liveness and readiness probes configured and returning healthy | S1: `/health` endpoint checked; code repo scan for probe config |
| 3 | Minimum replica baseline is met for production workload criticality | S1: `az containerapp show` replica count |
| 4 | Azure Monitor alert coverage exists for key failure signals | S1: alert fired correctly — verify coverage for health-check alert too |
| 5 | Service ownership and escalation path are defined | `orders-architecture.md` ownership table |
| 6 | On-call handoff notes are present in the knowledge base | `on-call-handoff.md` in knowledge base |

## Run

```bash
# Run this after S1-S3 so the agent has fresh incident context.
# Review guardrails from the governance runbook.
cat knowledge-base/platform-reliability-governance.md
```

Then open a new chat thread on [sre.azure.com](https://sre.azure.com) and ask the agent to run a governance review (see Suggested Prompts below).

## Suggested Prompts

Use any of these to trigger and explore the governance review:

- *"Run a platform reliability governance review for orders-api using the governance runbook"*
- *"Based on last night's incident, which guardrails failed and what's the risk score?"*
- *"Create GitHub backlog issues for every Warn or Fail guardrail with owners and due dates"*
- *"What would have prevented the S1 incident — map the root cause to specific guardrail gaps"*
- *"Generate a governance summary table I can share with the platform team"*

## Expected Output

The agent returns a governance summary with:
- Pass/Warn/Fail status per guardrail
- Overall risk score from the scoring model
- Direct references to S1/S2 incident evidence for any failing guardrail
- One GitHub backlog issue per Warn/Fail item with owner, due date, and measurable acceptance criteria

## Validation

```bash
# Ensure the governance runbook exists in knowledge base folder
ls knowledge-base | grep platform-reliability-governance.md

# Optional: capture resulting platform backlog issue(s)
gh issue list -R OWNER/REPO --search 'platform governance' --state open
```

## Knowledge Base

- [platform-reliability-governance.md](../knowledge-base/platform-reliability-governance.md)
- [change-risk-assessment.md](../knowledge-base/change-risk-assessment.md)
- [incident-report-template.md](../knowledge-base/incident-report-template.md)
- [on-call-handoff.md](../knowledge-base/on-call-handoff.md)
