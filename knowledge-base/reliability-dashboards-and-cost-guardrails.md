# Reliability Dashboards and Cost Guardrails

Use this guide to create read-only Azure Monitor dashboards or SRE Agent Live
Reports for the lab. Select only data sources connected and authorized for the
deployed environment. The lab supports Container Apps, App Service, and AKS;
reports should identify the active runtime rather than assume all three exist.

## Reliability command center

Use this prompt to create a Live Report:

```text
Create a read-only Live Report called "Reliability Command Center" for the
currently deployed Azure SRE Agent lab environment. Use connected
Application Insights, Log Analytics, and Azure Monitor data only.

Default to the last 24 hours and show the selected time range and data source.
Include total and failed requests, failure rate, p50/p95/p99 duration when
available, and a time chart for request volume, failures, and latency. Show
scenario or severity breakdowns only when the source data includes those fields.
Include an evidence table with timestamp, resource, operation or workload,
status/severity, summary, and correlation ID where available.

Show runtime-specific health only for resources that exist: Container Apps
replicas and revisions, App Service health and availability, or AKS workload
readiness and restart counts. Clearly label missing connectors, unsupported
metrics, and empty data; do not infer healthy status from missing telemetry.
Use connector queries on refresh. Do not use write tools or model-generated
incident facts.
```

## Report validation

Before sharing or relying on a report, verify that:

- Each chart and table states its time range, data source, and units.
- A no-data or unavailable-connector state is distinct from zero or healthy.
- Drill-down evidence includes timestamps and correlation identifiers when the
  source provides them.
- Runtime panels match deployed resources; absent runtime resources are omitted.
- Filters update all relevant visualizations, and refreshes reflect newly
  ingested telemetry.
- Summaries do not claim customer impact, diagnosis, or remediation without
  supporting evidence.
- Refreshing the report does not invoke write actions or unexpected model
  analysis.

## Cost guardrail

Cost reporting is advisory and read-only. Terraform configures the SRE Agent's
`monthly_agent_unit_limit`; this repository does not configure an Azure
subscription budget. Azure spend and budget status require an authorized Cost
Management data source. If either source is unavailable, label the value
unavailable and do not estimate it as actual spend.

Use this prompt to create a Live Report called "Lab Cost Guardrail":

```text
Create a read-only Live Report called "Lab Cost Guardrail" for the deployed
Azure SRE Agent lab environment. Use authorized Azure Cost Management and SRE
Agent consumption data only.

Show the reporting period and currency; actual Azure spend to date, forecast
when available, budget amount and percent consumed when a budget is configured,
and monthly agent-unit limit and consumption when those values are available.
Break Azure spend down by resource group and service where the source supports
it. Distinguish billed cost, forecast, configured limit, and estimate.

Use warning status at 80% and critical status at 100% of each configured
budget or usage limit. If a limit is not configured, show "No limit configured"
instead of assigning a threshold. Identify the largest cost changes and
potential savings as recommendations, not actions. Include the source and
timestamp for each value. If data is missing, stale, or access is denied, make
that explicit and do not substitute sample values.

Use connector queries only during refresh. Do not change budgets, scale
resources, stop workloads, or invoke other write actions.
```

Treat thresholds as report indicators, not Azure enforcement. Configure an
Azure budget and its notifications separately in Cost Management if the
environment needs an Azure spend limit alert. Review forecast assumptions and
regional pricing before acting on savings recommendations.
