# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with five progressive scenarios: detection and triage, autonomous remediation, issue triage, enterprise guardrails/connectors, and PIM elevation audit.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [Install Terraform](https://developer.hashicorp.com/terraform/install) |

> Note: the Terraform identity used for `apply` must be able to create Azure role assignments at the target resource scopes (for example, Owner or User Access Administrator).

## Quick Start

See [docs/quickstart.md](docs/quickstart.md) for step-by-step provisioning instructions.

## GitHub Actions

Deploy workflow: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
- Trigger: daily schedule and manual run.
- Inputs: `environment` (`demo`/`sbox`), `plan`, `apply`.
- OIDC secrets required: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

Destroy workflow: [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml)
- Trigger: daily schedule and manual run.
- Uses the same OIDC secrets as deploy.

## Scenarios

- [S1 - Detect and triage](scenarios/s1-detect-triage/README.md): trigger a 5xx incident and investigate in review mode.
- [S2 - Autonomous remediation](scenarios/s2-autonomous-remediation/README.md): break the running app with a `curl` and watch the agent detect, investigate, and remediate — runtime only, no redeploy.
- [S3 - Incident root cause investigation](scenarios/s3-incident-root-cause-investigation/README.md): investigate AKS regressions with GitHub repo evidence and HTTP trigger routing.
- [S4 - Alert Response and Incident Operations](scenarios/s4-alert-response-incident-operations/README.md): validate availability monitoring, alert routing, telemetry correlation, incident summaries, escalation, and recovery checks.
- [S5 - PIM Elevation Audit & Alignment](scenarios/s5-pim-elevation-audit/README.md): audit Entra PIM activations, correlate Azure Activity, and classify alignment; email summary.

### Scenario Steps

See [scenarios/README.md](scenarios/README.md) for detailed scenario steps and tfvars guidance.
See [docs/scenarios.md](docs/scenarios.md) for the full scenario catalogue and steps.

## Reference Recipes

The upstream `azmon-lawappinsights` recipe is integrated into this lab.
- Skills: [.github/skills/](.github/skills/)
- Agents and automations: [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/)
- Apply extras script: [scripts/apply-extras.sh](scripts/apply-extras.sh)

## Deployed Resources

- Core platform: resource group, managed identity, and SRE Agent resource.
- Observability: Log Analytics, Application Insights, and alert rules.
- Runtime: Container Apps by default; AKS only when `deploy_aks = true`.
