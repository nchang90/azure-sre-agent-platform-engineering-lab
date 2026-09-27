# agentic-incident-commander

Lightweight HMCTS-inspired Incident Commander recipe for cross-platform incident response.

## Purpose

This recipe runs a lightweight flow using:

1. Azure Monitor incident trigger
2. Dynatrace MCP + Azure telemetry correlation
3. Knowledge/runbook lookup
4. GitHub MCP + Jira MCP incident/work-item update
5. Remediation recommendation (recommend-only)

## Package layout

- `agent.json`
- `connectors.json`
- `expected-config.json`
- `tool-permissions.json`
- `agents/`
- `incident-platforms/azure-monitor/incident-filters/`

## Notes

- The flow is evidence-driven and recommendation-first.
- The final output separates confirmed findings from hypotheses.
- Remediation is never executed automatically in this scenario.
