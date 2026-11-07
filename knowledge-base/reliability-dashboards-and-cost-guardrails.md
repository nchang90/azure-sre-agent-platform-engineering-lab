# Reliability Dashboards and Cost Guardrails

Use these read-only report prompts with telemetry already connected to the Azure
SRE Agent. This lab has scenario-specific resources; select the deployed
scenario and runtime instead of expecting every panel or connector to exist.

## Choose the deployed scenario

| Scenario | Runtime and workload | Dashboard focus |
|---|---|---|
| S1 | Container Apps `orders-api` | HTTP 5xx detection and incident evidence |
| S2 | `orders-api` on Container Apps or the `conference-web` App Service, depending on the selected runtime | Requests, 5xx, P99 latency, and `/health` availability |
| S3 | AKS `checkout-api` | Pod readiness/restarts, Service endpoints, and routing evidence |
| S4 | `orders-api` on App Service | Alert routing, telemetry, and escalation evidence |
| S5 | No application runtime | PIM activation and Azure Activity audit evidence |
| S6 | Front Door and Container Apps chaos scenario | Backend health, probe results, and request failures |

The normal Terraform runtime selection is Container Apps unless a scenario or
explicit runtime selects App Service, AKS, or no application. S2 can use
Container Apps or App Service. Do not show runtime health panels for resources
that are not deployed.

## Reliability command center

Use this prompt to create a Live Report:

```text
Create a read-only Live Report called "Azure SRE Lab Reliability" for the
currently deployed scenario and environment. Use only the connected
Application Insights, Log Analytics, and Azure Monitor data for that deployment.
Default to the last 24 hours. State the environment, scenario, time range, data
source, and units. Do not assume all lab runtimes are deployed.

For orders-api, use the Application Insights requests data and filter by
cloud_RoleName == "orders-api" (or AppRoleName when that is the available
schema). Show request count, failed requests, 5xx count, failure rate, and
p50/p95/p99 duration over time. Include endpoint/operation, resultCode,
timestamp, and operation_Id in the evidence table where available. The repo's
S2 latency alert uses a P99 threshold of 2 seconds over five minutes; display
that as the configured alert threshold, not as a universal SLO.

For Container Apps, include orders-api replica/probe and container error
signals only when ContainerAppSystemLogs_CL is available. Use its
ContainerAppName_s, Reason_s, and Log_s fields; the repo's alerts look for
ReplicaUnhealthy/probe failures and back-off, crash, error, or terminated
events. A missing custom table is unavailable data, not a healthy service.

For the S2 App Service runtime, show the conference-web site's Http5xx metric
and the Application Insights /health web test. Identify the app as
conference-web (orders-api App Service in the scenario guide). Show the
configured alert thresholds and web-test availability without treating a
missing test result as success.

For S3 AKS, show checkout-api pod readiness and restart counts from
KubePodInventory, KubeEvents readiness probe failures, and the checkout-api
Service selector from KubeServices. Compare the selector labels with ready pod
labels from KubePodInventory to identify zero matching endpoints. Keep pod
health distinct from Service endpoint health: healthy pods can still have zero
Service endpoints. Use namespace, pod/service name, cluster, and TimeGenerated
for drill-down.

For S5, report PIM activation and correlated Azure Activity evidence only when
the required Entra and Activity data sources are connected. For S6, show
Front Door backend health/probe signals alongside orders-api requests; label
missing source data instead of inferring recovery.

Provide a no-data state for each unavailable table, metric, or connector.
Separate observed evidence from hypotheses; do not claim customer impact,
root cause, or remediation without supporting records. Use connector queries
on refresh only. Do not use write tools or model-generated incident facts.
```

The report may omit panels for unselected scenarios. See
[`infra/terraform/alerts.tf`](../infra/terraform/alerts.tf) for configured alert
signals and [`scenarios/README.md`](../scenarios/README.md) for scenario setup
and runtime guidance.

## Report validation

Before sharing or relying on a report, verify that:

- It names the actual environment and selected scenario/runtime.
- Each chart/table identifies its source, time range, and units.
- An empty result or missing connector/table is not represented as zero or
  healthy.
- Requests include operation/result details and correlation identifiers when
  available.
- S3 reporting treats healthy pods and Service endpoint availability as
  separate signals.
- The 2-second P99 threshold is identified as the configured orders-api alert
  threshold, not as a general target for every endpoint or runtime.
- Filters and refreshes update the evidence, and summaries remain evidence-
  backed and read-only.

## Cost guardrail

This repository configures an SRE Agent monthly unit limit through Terraform's
`monthly_agent_unit_limit` variable (default `10000`) and maps it to
`monthlyAgentUnitLimit`. Check the selected environment's Terraform inputs for
the deployed value. This is an agent usage limit, **not** an Azure spend budget.
The repository does not create an Azure subscription or resource-group budget.

Azure spend reporting needs separately authorized Cost Management data. Scope
the report to the deployed environment's resource group, such as
`rg-sre-lab-sbox`, `rg-sre-lab-dev`, `rg-sre-lab-sandbox`, or
`rg-sre-lab-summit-demo`, and state the actual scope used. Do not assume a
sample resource group name is the deployed scope. Agent-unit consumption also
needs an authorized source; Terraform's configured limit alone does not provide
consumption.

Use this prompt to create a read-only Live Report called "Azure SRE Lab Cost
Guardrail":

```text
Create a read-only Live Report called "Azure SRE Lab Cost Guardrail" for the
currently deployed Azure SRE Agent lab environment.

Report Azure billed cost and forecast only from authorized Cost Management
data. Identify subscription/resource-group scope, currency, billing period,
source, and last-updated time. Break down cost by resource group and service
when available. Do not assume a subscription budget or substitute example
amounts for actual billing data.

Report the configured SRE Agent monthly unit limit from the deployed Terraform
configuration and agent-unit consumption only if an authorized usage source
provides it. Keep the agent-unit limit and Azure spend in separate measures.
Show budget/limit percent only when both the configured limit and matching
consumption data are available.

Use warning at 80% and critical at 100% only for an actually configured budget
or usage limit. Otherwise show "No limit configured" or "Consumption data
unavailable." Distinguish billed actuals, forecasts, estimates, and limits.
Call out missing or stale data and list savings as recommendations only.
Refresh from read-only sources; do not change budgets, scale or stop resources,
or perform other write actions.
```

These thresholds are report indicators, not enforcement. Configure Azure
budgets and notifications separately in Cost Management if the environment
needs Azure spend alerts. Use
[`azure-cost`](../.github/skills/azure-cost/SKILL.md) for the cost-estimation
workflow and its guardrails.
