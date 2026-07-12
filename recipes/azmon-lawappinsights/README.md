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
- automations/incident-filters/azmon-sev01.yaml
- automations/scheduled-tasks/daily-health-check.yaml

## Lab Runtime Layout (existing)

This repo still uses its existing runtime apply flow for day-to-day operation:

- subagents in `recipes/azmon-lawappinsights/agents/`
- platform-specific plans in `recipes/azmon-lawappinsights/incident-platforms/`
- registration logic in `scripts/post-provision.sh`

Both layouts are kept so the lab is easy to run while also matching the upstream recipe shape.