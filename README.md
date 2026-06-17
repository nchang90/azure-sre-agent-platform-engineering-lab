# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with five progressive scenarios: detection and triage, autonomous remediation, issue triage, enterprise guardrails/connectors, and optional infrastructure resiliency validation.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [Install Terraform](https://developer.hashicorp.com/terraform/install) |

## Quick Start

1. Sign in to Azure and select your subscription.
2. Run `terraform -chdir=infra init`.
3. Run `terraform -chdir=infra apply -auto-approve -var-file=terraform.tfvars`.
4. Run `bash scripts/post-provision.sh`.

Cloud Shell note: if data-plane setup fails, run `az login --scope "https://azuresre.dev/.default"` and rerun `bash scripts/post-provision.sh --retry`.

## GitHub Actions

Deploy workflow: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)

- Trigger: manual run only.
- Inputs: `plan` and `apply` (both default to true).
- Secret required: `AZURE_CREDENTIALS`.
- Behavior: Terraform init, plan, optional apply, and optional post-provision.

Destroy workflow: [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml)

- Trigger: scheduled daily at 21:00 UTC and manual run.
- Manual safety input: `confirm_destroy=DESTROY`.

## Scenarios

- [S1 - Detect and triage](docs/scenario-s1-detect-triage.md): trigger a 5xx incident and investigate in review mode.
- [S2 - Autonomous remediation](docs/scenario-s2-autonomous-remediation.md): rerun S1 with automatic action mode.
- [S3 - Change issue triage](docs/scenario-s3-change-issue-triage.md): classify and respond to sample GitHub issues.
- [S4 - Enterprise Guardrails and Connectors at Scale](docs/scenario-s4-enterprise%20guardrails%20and%20connectors.md): demonstrate governed ServiceNow, GitHub Enterprise, and observability workflows with tool permissions and controlled handoffs.
- [S5 - Infrastructure Resiliency Manager + Chaos Validation (Optional)](docs/scenario-s5-chaos-validation.md): run goal-driven resiliency drills in non-production with tight blast radius and rollback guardrails.

### Per-scenario configuration

The lab deploys **one shared stack** — scenarios differ only by a couple of agent settings, not by infrastructure. Set them by editing your `environment/*.tfvars` file, or pass `-var` flags at apply time:

```bash
# Example: deploy the demo environment configured for S2 (autonomous remediation)
terraform -chdir=infra apply -var-file=environment/demo.tfvars \
  -var access_level=High -var action_mode=Automatic
```

| Scenario | `access_level` | `action_mode` | Connectors |
|---|---|---|---|
| S1 Detect & triage | `Low` | `Review` | — |
| S2 Autonomous remediation | `High` | `Automatic` | — |
| S3 Change issue triage | `Low` | `Review` | — (reuses the S1/S2 agent) |
| S4 Guardrails & connectors | `High` | `Review` | `enable_log_analytics_connector`, `enable_app_insights_connector`, `enable_azure_monitor_connector` = `true` |
| S5 Chaos validation (optional) | `High` | `Review` | Chaos Studio + Resiliency Manager are portal-configured (no Terraform) |

## Reference Recipes

The reusable logic from the upstream [Microsoft SRE Agent](https://github.com/microsoft/sre-agent/tree/main/sreagent-templates/recipes/azmon-lawappinsights) `azmon-lawappinsights` recipe is **already integrated** into the lab (translated from upstream's CLI schema into the lab's schema):

- Skills `investigate-azure-alerts` and `triage-app-errors` → [.github/skills/](.github/skills/)
- Subagents `alert-investigator` → `remediation-advisor` → [sre-config/agents/](sre-config/agents/)

These are registered with the agent by [scripts/post-provision.sh](scripts/post-provision.sh).

[recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/) keeps only the recipe pieces **not yet wired** into the lab — as a backlog/reference in upstream's schema: `config/hooks/` (deny-prod-deletes, require-approval-for-restarts), `config/common-prompts/`, and `automations/` (Sev0/Sev1 routing, daily health check).

## Deployed Components

- Resource group, managed identity, and SRE Agent resource.
- Log Analytics and Application Insights.
- Container Apps environment, ACR, and two services: orders-api and change-lookup.
- Alert rules and knowledge-base content.
- Subagents from [sre-config/agents](sre-config/agents).
