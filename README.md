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

- [S1 - Detect and triage](scenarios/s1-detect-triage/README.md): trigger a 5xx incident and investigate in review mode.
- [S2 - Autonomous remediation](scenarios/s2-autonomous-remediation/README.md): break the running app with a `curl` and watch the agent detect, investigate, and remediate — runtime only, no redeploy.
- [S3 - Change issue triage](scenarios/s3-change-issue-triage/README.md): classify and respond to sample GitHub issues.
- [S4 - Enterprise Guardrails and Connectors at Scale](scenarios/s4-enterprise-guardrails/README.md): demonstrate governed ServiceNow, GitHub Enterprise, and observability workflows with tool permissions and controlled handoffs.
- [S5 - PIM Elevation Audit & Alignment](docs/scenario-s5-pim-elevation-audit.md): audit Entra PIM activations, correlate Azure Activity, and classify alignment; email summary.

### Scenario Steps

See [docs/scenarios.md](docs/scenarios.md) for detailed scenario steps and tfvars guidance.

## Reference Recipes

The upstream `azmon-lawappinsights` recipe is integrated into this lab.
- Skills: [.github/skills/](.github/skills/)
- Agents and automations: [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/)
- Registration script: [scripts/post-provision.sh](scripts/post-provision.sh)

## Deployed Resources

- Core platform: resource group, managed identity, and SRE Agent resource.
- Observability: Log Analytics, Application Insights, and alert rules.
- Runtime: Container Apps environment, ACR, and the `orders-api` / `change-lookup` services.

## Repository structure

```
/infra
  /terraform
    /modules
    /environments
  /bicep
/src
  /orders-api
  /change-lookup
/scripts
/recipes
/scenarios
  /s1-detect-triage
  /s2-autonomous-remediation
  /s3-change-issue-triage
  /s4-enterprise-guardrails
/docs
  architecture.md
  troubleshooting.md
  quickstart.md
```
