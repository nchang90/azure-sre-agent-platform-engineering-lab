# On-Call Handoff Notes — Orders Platform

Use this document for shift-change handoffs and to satisfy on-call ownership checks in the enterprise guardrails and connectors scenario.

---

## Service Ownership

| Service | Primary owner | Escalation | On-call hours |
|---------|--------------|------------|---------------|
| orders-api | Orders Platform team | Platform team | Business hours (primary), Platform team (after-hours) |
| change-portal | Platform team | Platform team lead | 24/7 |
| change-lookup | Platform team | Platform team lead | 24/7 |

## Severity Mapping

| Severity | Condition | Response SLA |
|----------|-----------|-------------|
| Sev1 | 100% of orders-api requests failing; payments affected | 15 min |
| Sev2 | >50% error rate sustained >5 min; unauthorized deploy detected | 30 min |
| Sev3 | Elevated 5xx (<50%), single-revision degradation, non-critical path | 2 hours |
| Sev4 | Cosmetic, performance regression, single-user impact | Next business day |

## Escalation Path

1. On-call engineer checks the SRE Agent portal at [sre.azure.com](https://sre.azure.com) first — the agent may have already mitigated or produced a rollback recommendation.
2. If no agent action and Sev1/Sev2: page the Orders Platform team lead directly.
3. If infrastructure (Container Apps environment, ACR, networking): escalate to Platform team.
4. If more than one service is affected simultaneously: declare a major incident and bring in the Platform team lead and on-call manager.

## Incident Response Quick Reference

```bash
# Check current health and active CR
curl "<ORDERS_API_URL>/health" | jq .

# Check active revisions
az containerapp revision list -n orders-api -g <rg> -o table

# Check current alert state
az monitor alert list -g <rg> -o table

# Roll back to the stable image (lab)
bash scripts/reset-app.sh
```

## Handoff Checklist

Before handing off to the next shift, confirm the following:

- [ ] All active Sev1/Sev2 incidents are mitigated or have a documented mitigation plan
- [ ] The SRE Agent portal shows no unacknowledged incidents
- [ ] `orders-api /health` returns `status: healthy` and `activeChangeRequest` matches any planned CR
- [ ] Any changes made during the shift are backed by an active CR in `change-lookup`
- [ ] Incident records have been saved to agent memory (ask the agent: *"save this incident to memory"*)
- [ ] Any new runbook gaps discovered during the shift are filed as GitHub issues with the `runbook-gap` label

## Notes for the SRE Agent

When the SRE Agent runs the enterprise guardrails and connectors scenario (S4), it checks this file to confirm on-call handoff notes (ownership, escalation, and severity mapping) are defined. If this file is missing or incomplete, the on-call ownership control should be flagged as failed.

The agent should:
1. Verify the service ownership table covers all production services.
2. Verify the escalation path is specific (named roles, not generic "the team").
3. Verify the severity mapping defines measurable response SLAs.
4. Reference this document in any incident report under the **Escalation** section.
