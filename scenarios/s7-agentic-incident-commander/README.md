# S7 — Agentic Incident Commander (HMCTS-inspired)

**Persona:** Incident Commander / On-call SRE  
**Runtime:** Monitoring-first (cross-platform)  
**Recipe:** `agentic-incident-commander`

---

## Scenario objective

Run a full incident-command workflow:

1. Service issue observed
2. Observability correlation (Dynatrace + Azure telemetry)
3. Agent investigation
4. Runbook/knowledge lookup
5. Incident/work-item update
6. Remediation recommendation

---

## Trigger

Start from an Azure Monitor or ServiceNow incident for `orders-api`.

---

## Expected telemetry evidence

- Fired alert details and severity
- Failed request and exception patterns
- Dependency failure signals
- Time-window correlation across available telemetry sources

---

## Investigation path

Handoff chain used by this scenario:

```text
incident-commander-intake
  -> cross-platform-observability-investigator
  -> runbook-knowledge-analyst
  -> incident-workitem-writer
  -> remediation-recommendation-agent
```

---

## Incident artifact output

The chain produces an operator-ready incident update including:

- Impact (confirmed)
- Timeline
- Evidence summary
- Current status
- Owner and next action

---

## Remediation recommendation output

The final output provides recommendation-only actions with:

- priority order
- risk level
- rollback notes
- approval requirement

No remediation is claimed as executed unless a human explicitly approves and performs it.
