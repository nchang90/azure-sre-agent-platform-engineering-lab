# azmon-lawappinsights

Local reference for the upstream `azmon-lawappinsights` recipe from the Microsoft SRE Agent templates:

- Upstream source: https://github.com/microsoft/sre-agent/tree/main/sreagent-templates/recipes/azmon-lawappinsights
- Purpose: Azure Monitor agent with Log Analytics and App Insights for alert investigation and application-error triage.

## Mapped Into This Lab

This lab does not copy the upstream recipe verbatim. It translates the recipe into the lab's Terraform and SRE config layout.

| Upstream recipe area | Lab location |
|---|---|
| Skills `investigate-azure-alerts`, `triage-app-errors` | `.github/skills/` |
| Subagents `alert-investigator`, `remediation-advisor` | `recipes/azmon-lawappinsights/agents/` |
| Incident filter `azmon-sev01` | Registered inline by `scripts/post-provision.sh` (gated by `enable_sev01_incident_filter`) |
| Scheduled task `daily-health-check` | Registered inline by `scripts/post-provision.sh` (gated by `enable_daily_health_check`) |
| ServiceNow incident platform | `recipes/azmon-lawappinsights/incident-platforms/servicenow/` |
| Registration flow | `scripts/post-provision.sh` |

## Runtime Notes

- The Terraform layer exposes toggle outputs for `enable_sev01_incident_filter` and `enable_daily_health_check`.
- `scripts/post-provision.sh` reads those outputs and registers the corresponding response plan and scheduled task with the SRE Agent data plane.
- The repo also keeps a lab-specific `orders-api-errors` response plan in `scripts/post-provision.sh` for the scenario walkthroughs.
- The ServiceNow recipe mirror lives under `recipes/azmon-lawappinsights/incident-platforms/servicenow/` and is used when the SRE Agent ServiceNow connector is available.

## Not Yet Wired

These upstream recipe items are intentionally tracked as backlog/reference rather than active lab config:

- `config/hooks/deny-prod-deletes`
- `config/hooks/require-approval-for-restarts`
- `config/common-prompts/investigation-guidelines`
- `config/common-prompts/safety-rules`

If those are added later, keep the authoritative runnable config in the lab's existing layout and update this mapping document.