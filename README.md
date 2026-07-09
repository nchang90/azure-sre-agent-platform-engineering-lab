# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with four progressive scenarios: detection and triage, autonomous remediation, issue triage, and enterprise guardrails/connectors.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [Install Terraform](https://developer.hashicorp.com/terraform/install) |

## Quick Start

See [docs/quickstart.md](docs/quickstart.md) for step-by-step provisioning instructions.

## GitHub Actions

Deploy workflow: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
- Trigger: daily schedule and manual run.
- Inputs: `environment` (`demo`/`sbox`), `plan`, `apply`.
- Secret required: `AZURE_CREDENTIALS`.

Destroy workflow: [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml)
- Trigger: daily schedule and manual run.

## Scenarios

See [docs/scenarios.md](docs/scenarios.md) for the full scenario catalogue and steps.

## Reference Recipes

The upstream `azmon-lawappinsights` recipe is integrated into this lab.
- Skills: [.github/skills/](.github/skills/)
- Agents and automations: [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/)
- Registration script: [scripts/post-provision.sh](scripts/post-provision.sh)

## Deployed Resources

- Core platform: resource group, managed identity, and SRE Agent resource.
- Observability: Log Analytics, Application Insights, and alert rules.
- Runtime: Container Apps environment, ACR, and the `orders-api` / `change-lookup` services.
