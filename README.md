# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with four progressive scenarios: detection and triage, autonomous remediation, issue triage, and enterprise guardrails/connectors.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [Install Terraform](https://developer.hashicorp.com/terraform/install) |

## Quick Start (S2-S4 Terraform Path)

1. Sign in to Azure and select your subscription.
2. Run `terraform -chdir=infra/terraform init`.
3. Run `terraform -chdir=infra/terraform apply -auto-approve -var-file=environments/demo.tfvars`.
4. Run `bash scripts/post-provision.sh`.

## GitHub Actions

Deploy workflow: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
- Trigger: daily schedule and manual run.
- Inputs: `environment` (`demo`/`sbox`), `plan`, `apply`.
- Secret required: `AZURE_CREDENTIALS`.

Destroy workflow: [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml)
- Trigger: daily schedule and manual run.

## Scenarios

- [S1 - Detect and triage](docs/scenario-s1-detect-triage.md): trigger a 5xx incident and investigate in review mode.
- [S2 - Autonomous remediation](docs/scenario-s2-autonomous-remediation.md): break the running app with a `curl` and watch the agent detect, investigate, and remediate — runtime only, no redeploy.
- [S3 - Change issue triage](docs/scenario-s3-change-issue-triage.md): classify and respond to sample GitHub issues.
- [S4 - Enterprise Guardrails and Connectors at Scale](docs/scenario-s4-enterprise-guardrails-connectors.md): demonstrate governed ServiceNow, GitHub Enterprise, and observability workflows with tool permissions and controlled handoffs.
- [S5 - PIM Elevation Audit & Alignment](docs/scenario-s5-pim-elevation-audit.md): daily audit of PIM activations, activity correlation, and alignment classification with email report.

### Scenario Steps (Flexible)

Any scenario can use any file in `infra/terraform/environments/*.tfvars`, or a new custom tfvars file you create. The table below shows recommended defaults only.

| Scenario | Recommended tfvars | Required post-provision step | Optional step |
|---|---|---|---|
| S1 Detect and triage | N/A (uses `azd`/Bicep) | `azd env new s1-demo` then `azd provision` | `azd env get-values` |
| S2 Autonomous remediation | Any existing tfvars (recommended: `environments/sbox.tfvars`) or a new custom tfvars | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S3 Change issue triage | `environments/demo.tfvars` or `environments/sbox.tfvars` | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S4 Guardrails/connectors | `environments/demo.tfvars` | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (when running GitHub-enabled flows) |

## Reference Recipes

The upstream `azmon-lawappinsights` recipe is integrated into this lab.
- Skills: [.github/skills/](.github/skills/)
- Agents and automations: [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/)
- Registration script: [scripts/post-provision.sh](scripts/post-provision.sh)

## Deployed Resources

- Core platform: resource group, managed identity, and SRE Agent resource.
- Observability: Log Analytics, Application Insights, and alert rules.
- Runtime: Container Apps environment, ACR, and the `orders-api` / `change-lookup` services.
