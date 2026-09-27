# agentic-incident-commander

HMCTS-inspired incident commander recipe for cross-platform service incidents.

## Purpose

This recipe models the end-to-end flow:

1. Service issue trigger
2. Observability correlation (Dynatrace + Azure telemetry)
3. Agent-led investigation
4. Runbook/knowledge lookup
5. Incident/work-item write-back
6. Remediation recommendation (recommend-only)

## Package layout

- `agent.json`
- `connectors.json`
- `expected-config.json`
- `tool-permissions.json`
- `agents/`
- `incident-platforms/azure-monitor/incident-filters/`
- `incident-platforms/servicenow/incident-filters/`

## Notes

- This recipe contributes a five-agent handoff chain.
- The final output distinguishes facts from hypotheses.
- Remediation is recommendation-only unless explicit human approval is provided.
