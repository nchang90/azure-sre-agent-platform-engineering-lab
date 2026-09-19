# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with six progressive scenarios: detection and triage, web-api deployment-regression remediation, AKS multi-agent investigation, alert operations, PIM elevation audit, and Front Door incident response.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`brew install azure-cli`)
- [Terraform 1.5+](https://developer.hashicorp.com/terraform/install) (`brew install terraform`)
- An identity able to create role assignments at the target scopes (Owner or User Access Administrator) — see [`infra/terraform/rbac.tf`](infra/terraform/rbac.tf).

## Scenarios

| Scenario | Purpose |
|---|---|
| [S1 - Detect and triage](scenarios/s1-detect-triage/README.md) | Trigger a 5xx incident and investigate in review mode. |
| [S2 - AI Web App incident remediation](scenarios/s2-autonomous-remediation/README.md) | Investigate frontend-ok/backend-failing `/api/orders` 500s and safely restore service. |
| [S3 - AKS root-cause investigation](scenarios/s3-incident-root-cause-investigation/README.md) | Delegate AKS routing/state investigation to specialist subagents. |
| [S4 - Alert response & incident ops](scenarios/s4-alert-response-incident-operations/README.md) | Validate monitoring, alert routing, telemetry, and escalation. |
| [S5 - PIM elevation audit](scenarios/s5-pim-elevation-audit/README.md) | Audit Entra PIM activations and correlate Azure Activity. |
| [S6 - Front Door incident response](scenarios/s6-frontdoor-incident-response/README.md) | Inject backend faults with Chaos Studio and correlate Front Door health probes with App Insights. |

Steps and tfvars guidance: [scenarios/README.md](scenarios/README.md).

## Deploy

`azd up` (see [azure.yaml](azure.yaml)), or run the workflows:

- [`deploy.yml`](.github/workflows/deploy.yml) — daily schedule + manual. Inputs: `environment` (`demo`/`sbox`/`dev`), S2 `runtime` (`webapp` default or `containerapps`), `plan`, `apply`.
- [`destroy.yml`](.github/workflows/destroy.yml) — daily schedule + manual.

State lives in the `tfstate` container of the `terraformstatesboxprd` storage account (`terraform-tfstate` resource group), one key per environment — see [`infra/terraform/backend/`](infra/terraform/backend/).

### Workflow authentication

Workflows use workload identity federation — no client secrets. The user-assigned identity `uami-github` (`terraform-tfstate` resource group) holds `Contributor` and `User Access Administrator` at subscription scope, with a federated credential pinned to `repo:nchang90/azure-sre-agent-platform-engineering-lab:ref:refs/heads/main` (issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`), so only runs on `main` can obtain a token.

Both `azure/login@v3` and Terraform use it: `ARM_USE_OIDC=true` plus `ARM_CLIENT_ID`/`ARM_TENANT_ID`/`ARM_SUBSCRIPTION_ID` cover the `azurerm` and `azapi` providers *and* the state backend, so Terraform never falls back to a CLI token that cannot be refreshed mid-`apply`. Workflows declare `permissions: id-token: write`; repository secrets are `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.

To add a branch or environment, create another federated credential rather than loosening the subject:

```bash
az identity federated-credential create \
  --name github-<branch> \
  --identity-name uami-github \
  --resource-group terraform-tfstate \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:nchang90/azure-sre-agent-platform-engineering-lab:ref:refs/heads/<branch>" \
  --audiences api://AzureADTokenExchange
```

## Layout

```
infra/           # Terraform, Bicep modules (AVM-based), K8s manifests for Orders API
scenarios/       # Progressive learning scenarios, each with its own README
knowledge-base/  # Runbooks by service, on-call handoff, incident report, issue triage
recipes/         # Reference agent configs: azmon-lawappinsights, dynatrace-servicenow
src/             # orders-api (.NET sample), change-lookup (git change discovery)
scripts/         # Automation & deployment scripts
.github/         # Workflows & Copilot skills
```

The upstream `azmon-lawappinsights` recipe is integrated here: [.github/skills/](.github/skills/), [recipes/azmon-lawappinsights/](recipes/azmon-lawappinsights/), [scripts/apply-extras.sh](scripts/apply-extras.sh).
