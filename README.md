# Azure SRE Agent - Platform Engineering Lab

Hands-on Azure SRE Agent lab with six progressive incident scenarios.

**Prerequisites:** [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), [Terraform 1.5+](https://developer.hashicorp.com/terraform/install), and an identity that can create role assignments at the target scopes (Owner or User Access Administrator) — see [`infra/terraform/rbac.tf`](infra/terraform/rbac.tf).

## Scenarios

| Scenario | Purpose |
|---|---|
| [S1 - Detect and triage](scenarios/s1-detect-triage/README.md) | Trigger a 5xx incident and investigate in review mode. |
| [S2 - AI Web App incident remediation](scenarios/s2-autonomous-remediation/README.md) | **`orders-api` on Azure App Service.** A Web App backend regression is causing `/api/orders` failures. Azure Monitor and Application Insights drive recovery. |
| [S3 - AKS root-cause investigation](scenarios/s3-incident-root-cause-investigation/README.md) | **Checkout API on AKS.** The Checkout API is unavailable because Kubernetes routing has zero endpoints. ServiceNow triggers the investigation and receives the RCA. |
| [S4 - Alert response & incident ops](scenarios/s4-alert-response-incident-operations/README.md) | Validate monitoring, alert routing, telemetry, and escalation. |
| [S5 - PIM elevation audit](scenarios/s5-pim-elevation-audit/README.md) | Audit Entra PIM activations and correlate Azure Activity. |
| [S6 - Front Door incident response](scenarios/s6-frontdoor-incident-response/README.md) | Inject backend faults with Chaos Studio and correlate Front Door health probes with App Insights. |

Steps and tfvars guidance: [scenarios/README.md](scenarios/README.md).

## Deploy

`azd up` (see [azure.yaml](azure.yaml)), or run the workflows:

- [`deploy.yml`](.github/workflows/deploy.yml) — daily schedule + manual. Inputs: `environment` (`demo`/`sbox`/`dev`), S2 `runtime` (`containerapps` default or `webapp`), `plan`, `apply`.
- [`destroy.yml`](.github/workflows/destroy.yml) — daily schedule + manual.

State lives in the `tfstate` container of the `terraformstatesboxprd` storage account (`terraform-tfstate` resource group), one key per environment — see [`infra/terraform/backend/`](infra/terraform/backend/).

Workflows authenticate with workload identity federation, no client secrets: the `uami-github` identity is pinned to `refs/heads/main`, and `ARM_USE_OIDC=true` plus `ARM_CLIENT_ID`/`ARM_TENANT_ID`/`ARM_SUBSCRIPTION_ID` covers both the providers and the state backend. To add a branch, add another federated credential rather than loosening the subject.

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
