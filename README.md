# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with five progressive scenarios: detection and triage, web-api deployment-regression remediation, AKS multi-agent investigation, issue triage, and PIM elevation audit.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [Install Terraform](https://developer.hashicorp.com/terraform/install) |

> Note: the Terraform identity used for `apply` must be able to create Azure role assignments at the target resource scopes (for example, Owner or User Access Administrator).

## Quick Start

See [docs/quickstart.md](docs/quickstart.md) for step-by-step provisioning instructions.

## GitHub Actions

### Authentication (OIDC federated identity)

Workflows authenticate to Azure with **workload identity federation** — no client secrets are
stored anywhere. GitHub mints a short-lived OIDC token, and Entra ID exchanges it for an Azure
access token.

The identity is the user-assigned managed identity `uami-github` in the `terraform-tfstate`
resource group, with a federated credential scoped to this repository:

| Setting | Value |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | `repo:nchang90/azure-sre-agent-platform-engineering-lab:ref:refs/heads/main` |
| Audience | `api://AzureADTokenExchange` |

Because the subject is pinned to `refs/heads/main`, only workflow runs on `main` (scheduled or
manually dispatched) can obtain a token. Runs from branches or forks are rejected by Entra ID.

Roles held by the identity at subscription scope:

- `Contributor` — create and manage lab resources.
- `User Access Administrator` — required because [`infra/terraform/rbac.tf`](infra/terraform/rbac.tf)
  creates role assignments for the SRE Agent.

Both the Azure CLI and Terraform use this identity:

- `azure/login@v3` is given `client-id`/`tenant-id`/`subscription-id` with no `client-secret`.
- Terraform authenticates natively via `ARM_USE_OIDC=true` plus `ARM_CLIENT_ID`, `ARM_TENANT_ID`,
  and `ARM_SUBSCRIPTION_ID`. This applies to the `azurerm` and `azapi` providers *and* to the
  `azurerm` state backend, so Terraform never falls back to the CLI token — which cannot be
  refreshed mid-run and would otherwise expire during a long `apply`.

Both workflows therefore declare `permissions: id-token: write`.

Repository secrets required (all are non-sensitive identifiers, stored as secrets by convention):
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

To add another branch or a GitHub environment, create an additional federated credential rather
than loosening the existing subject:

```bash
az identity federated-credential create \
  --name github-<branch> \
  --identity-name uami-github \
  --resource-group terraform-tfstate \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:nchang90/azure-sre-agent-platform-engineering-lab:ref:refs/heads/<branch>" \
  --audiences api://AzureADTokenExchange
```

### Workflows

Deploy workflow: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
- Trigger: daily schedule and manual run.
- Inputs: `environment` (`demo`/`sbox`/`dev`), S2 `runtime` (`containerapps`/`webapp`), `plan`, `apply`.

Destroy workflow: [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml)
- Trigger: daily schedule and manual run.
- Uses the same federated identity as deploy.

Terraform state lives in the `tfstate` container of the `terraformstatesboxprd` storage account
(`terraform-tfstate` resource group), one key per environment — see
[`infra/terraform/backend/`](infra/terraform/backend/).

## Scenarios

| Scenario | Status | Purpose |
|----------|--------|---------|
| [S1 - Detect and triage](scenarios/s1-detect-triage/README.md) | Complete | Trigger a 5xx incident and investigate in review mode. |
| [S2 - AI Web App production incident remediation](scenarios/s2-autonomous-remediation/README.md) | Complete | Investigate frontend-ok/backend-failing post-deployment `/api/orders` 500s and safely restore service. |
| [S3 - AKS multi-agent root-cause investigation](scenarios/s3-incident-root-cause-investigation/README.md) | Complete | Delegate AKS routing/state investigation to specialist subagents and synthesize findings. |
| [S4 - Alert Response & Incident Operations](scenarios/s4-alert-response-incident-operations/README.md) | Complete | Validate monitoring, alert routing, telemetry, and escalation. |
| [S5 - PIM Elevation Audit](scenarios/s5-pim-elevation-audit/README.md) | Complete | Audit Entra PIM activations and correlate Azure Activity. |

### Scenario Steps

See [scenarios/README.md](scenarios/README.md) for detailed scenario steps and tfvars guidance.
See [docs/scenarios.md](docs/scenarios.md) for the full scenario catalogue and steps.

## Reference Recipes

The upstream `azmon-lawappinsights` recipe is integrated into this lab.
- Skills: [.github/skills/](.github/skills/)
- Agents and automations: [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/)
- Apply extras script: [scripts/apply-extras.sh](scripts/apply-extras.sh)

## Directory Structure

```
.
├── images/               # Architecture diagrams & screenshots
├── infra/                # Infrastructure as Code
│   ├── bicep/            # Azure Bicep modules (AVM-based)
│   │   └── modules/      # Reusable: identity, loganalytics, containerapps, frontdoor, sre-agent
│   └── k8s/              # Kubernetes manifests for Orders API
├── knowledge-base/       # Runbooks & incident guides
│   ├── runbooks/         # Organized by service (containers, frontdoor, aks, monitoring)
│   ├── on-call-handoff.md
│   ├── incident-report.md
│   └── github-issue-triage.md
├── recipes/              # Reference agent configurations
│   ├── azmon-lawappinsights/  # Azure Monitor + Log Analytics + App Insights
│   └── dynatrace-servicenow/  # Dynatrace + ServiceNow integration
├── scenarios/            # Progressive learning scenarios (S1-S5)
│   └── */README.md       # Each scenario has its own guide
├── src/                  # Source code
│   ├── orders-api/       # .NET sample microservice
│   └── change-lookup/    # Git change discovery tool
├── scripts/              # Automation & deployment scripts
├── .github/              # GitHub workflows & Copilot skills
├── azure.yaml            # Azure Developer CLI manifest
└── sre-agent.sln         # Visual Studio solution
```

## Getting Started

1. **See this README** — Overview & scenarios table
2. **Choose a scenario** — [Scenarios](#scenarios) section  
3. **Follow scenario README** — Each `scenarios/s*/README.md` has step-by-step guide
4. **Use knowledge base** — [knowledge-base/](knowledge-base/) for runbooks during incidents
5. **Deploy infra** — `azd up` (see `azure.yaml`)

## Key Features

✅ **Progressive Scenarios** — Learn SRE agent capabilities from detection to autonomous remediation  
✅ **Production-Ready Code** — Bicep modules (AVM-aligned), Kubernetes manifests, GitHub Actions  
✅ **Incident Runbooks** — Organized by service, with KQL queries and remediation steps  
✅ **Agent Integration** — Azure SRE Agent with skills, automations, and response plans  
✅ **Reference Recipes** — Azure Monitor, Log Analytics, App Insights, and ServiceNow integration  

## Deployed Resources

- Core platform: resource group, managed identity, and SRE Agent resource.
- Observability: Log Analytics, Application Insights, and alert rules.
