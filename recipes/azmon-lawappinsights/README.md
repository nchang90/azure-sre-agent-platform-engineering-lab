# azmon-lawappinsights

Upstream-style mirror of the Microsoft SRE Agent template recipe:

- Source: https://github.com/microsoft/sre-agent/tree/main/sreagent-templates/recipes/azmon-lawappinsights
- Purpose: Azure Monitor alert response with App Insights and Log Analytics context.

## Package Layout (template-style)

- agent.json
- connectors.json
- expected-config.json
- tool-permissions.json
- automations/incident-platforms/azmonitor.yaml
- incident-platforms/azure-monitor/incident-filters/all-incidents.yaml
- automations/scheduled-tasks/daily-health-check.yaml

## Lab Runtime Layout (existing)

This repo still uses its existing runtime apply flow for day-to-day operation:

- subagents in `recipes/azmon-lawappinsights/agents/`
- one shared scenario response plan in `recipes/azmon-lawappinsights/incident-platforms/`
- registration logic in `scripts/apply-extras.sh`

Both layouts are kept so the lab is easy to run while also matching the upstream recipe shape.