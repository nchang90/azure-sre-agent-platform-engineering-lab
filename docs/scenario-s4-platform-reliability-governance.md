# S4 - Platform Reliability Governance

Persona: Platform Engineering

## Story

After incident triage and remediation, the platform team runs a governance pass to prevent recurrence. The agent evaluates core reliability guardrails, scores risk, and turns gaps into concrete backlog work for platform and service teams.

## Scenario Diagram

<img src="../images/story4.png" alt="change issue triage" width="600" />  


## Run

```bash
# Run this after S1-S3 so the agent has fresh incident context.
# Review guardrails from the governance runbook.
cat knowledge-base/platform-reliability-governance.md
```

## Guardrails Evaluated

1. Every production deploy has a linked and active change request.
2. Liveness and readiness probes are configured and returning healthy.
3. Minimum replica baseline is met for production workload criticality.
4. Azure Monitor alert coverage exists for key failure signals.
5. Service ownership and escalation path are defined.

## Expected Output

The agent returns a governance summary with pass/warn/fail status per guardrail, an overall risk score, and explicit remediation actions with owners.

## Validation

```bash
# Ensure the governance runbook exists in knowledge base folder
ls knowledge-base | grep platform-reliability-governance.md

# Optional: capture resulting platform backlog issue(s)
# gh issue list -R OWNER/REPO --search 'platform governance' --state open
```

## Knowledge Base

- [platform-reliability-governance.md](../knowledge-base/platform-reliability-governance.md)
- [change-risk-assessment.md](../knowledge-base/change-risk-assessment.md)
- [incident-report-template.md](../knowledge-base/incident-report-template.md)
