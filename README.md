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

| Scenario | Status | Purpose |
|----------|--------|---------|
| [S1 - Detect and triage](scenarios/s1-detect-triage/README.md) | Complete | Trigger a 5xx incident and investigate in review mode. |
| [S2 - Autonomous remediation](scenarios/s2-autonomous-remediation/README.md) | Complete | Break the running app and watch the agent detect, investigate, and remediate. |
| [S3 - Incident root cause investigation](scenarios/s3-incident-root-cause-investigation/README.md) | Complete | Investigate AKS regressions with GitHub repo evidence and routing. |
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
