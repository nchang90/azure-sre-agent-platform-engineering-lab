# Change Management Runbook

Use this guide when a customer issue appears to be related to a recent change request (CR). The SRE Agent uses this runbook to decide whether the report is likely a change-related incident, a policy violation, or a customer question that needs clarification.

---

## When to use this runbook

Apply this guidance when:

- the issue title or body references a CR number such as `CHG0030001`
- the customer says the issue started after a deploy, rollout, or maintenance window
- the issue looks tied to a recent revision shipped through the paved road
- the report mentions a deployment that skipped approval or was not linked to a change

---

## Inputs to collect

| Input | Source |
|-------|--------|
| Change request metadata | `change-lookup /changes/{cr}` |
| Active change window | `change-lookup /changes/active/now` |
| Issue body and comments | GitHub issue content |
| Related deployment context | `orders-api` health and deployment metadata |

---

## Decision flow

1. Confirm whether the issue references a CR.
2. Check whether the CR is active, approved, completed, or missing.
3. Compare the issue timing with the change window or rollout window.
4. Determine whether the report is:
   - a likely change-related incident
   - a policy violation / unauthorized change
   - a generic bug unrelated to the CR
   - a question that needs more details
5. Recommend the next action:
   - observe
   - escalate
   - hold the rollout
   - rollback the revision
   - ask the customer for more information

---

## Output guidance

When the SRE Agent posts a triage comment, it should include:

- the linked CR number, if one exists
- the CR status and any available risk signal
- a short summary of the customer report
- the recommended next steps

Example:

```text
🤖 **SRE Agent**

**Classification:** Change-Related-Incident
**Linked CR:** CHG0030001 — orders-api deployment
**CR Status:** Approved / Medium risk

**Summary:** Customer reports 500s after the latest deployment.

**Recommended next steps:**
- Correlate the failure window with the active revision
- Verify health check and error rate trends
- Roll back if the error rate remains elevated
```

---

## Hard stops

Escalate immediately if any of these are true:

- there is no rollback path
- the issue affects authentication, billing, or another critical path
- the CR does not exist or is not approved
- the same service recently had a similar incident

---

## Related docs

- [github-issue-triage.md](./github-issue-triage.md)
- [orders-architecture.md](./orders-architecture.md)
