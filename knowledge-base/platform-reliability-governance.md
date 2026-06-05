# Platform Reliability Governance Runbook

## Purpose

Use this runbook after an incident or before high-risk production changes to enforce platform reliability guardrails and reduce repeat failures.

## Guardrail Checklist

1. Change governance
- Production deploy is linked to an active change request.
- Change request includes owner, risk tier, and rollback plan.

2. Workload health baseline
- Liveness probe configured and passing.
- Readiness probe configured and passing.
- Resource requests and limits are set.
- Minimum replica baseline meets service tier requirements.

3. Monitoring and alerting
- Service has 5xx/error-rate alert.
- Service has health-check or availability alert.
- Alert has response routing configured to the SRE agent.

4. Operational ownership
- Service owner and escalation contact are defined.
- Incident severity mapping exists.
- On-call handoff notes are present in knowledge base.

## Scoring Model

- Pass: all mandatory controls met.
- Warn: one non-critical control missing.
- Fail: any critical control missing.

Critical controls:
- Active CR linkage for production change.
- Health probes configured.
- At least one failure alert and one availability alert.

## Remediation Actions

When status is Warn or Fail, create backlog items with:
- title: short reliability gap statement
- owner: platform team or service team
- due date: target fix date
- evidence: observed incident or config state
- acceptance criteria: measurable fix outcome

## Output Template

- Service:
- Date:
- Guardrail status: Pass/Warn/Fail
- Missing controls:
- Risk score:
- Recommended actions:
- Owners:
- Due dates:
