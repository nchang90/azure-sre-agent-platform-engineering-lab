# S7 — Agentic Incident Commander (Lightweight, HMCTS-inspired)

**Persona:** Incident Commander / On-call SRE  
**Runtime:** Monitoring-first (cross-platform)  
**Recipe:** `agentic-incident-commander`

---

## Scenario objective

Run a lightweight Incident Commander workflow using:

1. Azure Monitor trigger
2. Dynatrace MCP + Azure telemetry correlation
3. Knowledge files / runbook lookup
4. GitHub MCP + Jira MCP incident update
5. Remediation recommendation (no auto-execution)

---

## Trigger

Start from an Azure Monitor incident for `orders-api`.

---

## Expected telemetry evidence

- Fired alert details and severity
- Failed request and exception patterns
- Dependency failure signals
- Time-window correlation between Azure telemetry and Dynatrace MCP evidence

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

The chain produces operator-ready updates for GitHub MCP and Jira MCP including:

- confirmed impact
- timeline
- evidence summary
- current status
- owner and next action

---

## Remediation recommendation output

The final output provides recommendation-only actions with:

- priority order
- risk level
- rollback notes
- approval requirement

No remediation is executed automatically in S7.
