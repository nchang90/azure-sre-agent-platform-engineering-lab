# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with four progressive scenarios: detection and triage, autonomous remediation, issue triage, and reliability governance.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [guide](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [guide](https://developer.hashicorp.com/terraform/install) |

## Quick Start (Local)

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
- [S4 - Platform reliability governance](docs/scenario-s4-platform-reliability-governance.md): run a governance review and create backlog actions.

## Deployed Components

- Resource group, managed identity, and SRE Agent resource.
- Log Analytics and Application Insights.
- Container Apps environment, ACR, and two services: orders-api and change-lookup.
- Alert rules and knowledge-base content.
- Subagents from [sre-config/agents](sre-config/agents).
