# Azure SRE Agent — Platform Engineering Lab

A hands-on lab for Azure SRE Agent. Four scenarios that build on each other, one `azd up`, ~10 min.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [guide](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [guide](https://developer.hashicorp.com/terraform/install) |

## Quick Start



> **Cloud Shell:** data-plane items (subagents) need `az login --scope "https://azuresre.dev/.default"`, or apply later with `bash scripts/post-provision.sh --retry`.

## Deployment Automation

This repo deploys automatically with GitHub Actions using [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

- Triggered on push to `main` and manual run (`workflow_dispatch`).
- Logs in to Azure using the `AZURE_CREDENTIALS` repository secret.
- Runs `terraform -chdir=infra init` and `terraform -chdir=infra apply -auto-approve -var-file=terraform.tfvars`.
- Runs `bash scripts/post-provision.sh` after Terraform to configure data-plane artifacts.

Set the `AZURE_CREDENTIALS` secret in your repository before relying on CI deployment.

## Scenarios

One storyline: an incident breaks the app, the agent remediates it, the next morning it triages customer fallout, and then the platform team closes the loop with governance guardrails.

| Scenario | Persona | Trigger | What the agent does |
|---|---|---|---|
| [S1 — Detect & triage](docs/scenario-s1-detect-triage.md) | On-call / IT Ops | `bash scripts/break-app.sh` | Picks up the 5xx alert, correlates a rogue deploy, finds no change request, recommends a rollback (Review mode) |
| [S2 — Autonomous remediation](docs/scenario-s2-autonomous-remediation.md) | Platform / SRE | Re-run S1 in `High` / `Automatic` mode | Acts on its own — rolls the bad revision back without waiting for a human |
| [S3 — Change issue triage](docs/scenario-s3-change-issue-triage.md) | Support / Automation | `bash scripts/create-sample-issues.sh OWNER/REPO` | Reviews customer issues, links them to change requests, classifies, posts triage comments |
| [S4 — Platform reliability governance](docs/scenario-s4-platform-reliability-governance.md) | Platform Engineering | Run the governance checklist and policy review | Evaluates guardrails (CR linkage, probes, replicas, alerts), scores risk, and files platform backlog actions |

## What Gets Deployed

| Resource | Notes |
|---|---|
| Resource Group + Managed Identity | Lab resources + agent's RBAC identity |
| Log Analytics + Application Insights | Logs, metrics, tracing |
| SRE Agent | `Microsoft.App/agents` via `azapi` |
| Container Registry + Apps Environment | Image builds + runtime |
| `orders-api` (.NET 9) | Monitored workload — supports fault injection |
| `change-lookup` (Python) | ServiceNow CR proxy (mock) — agent checks for an authorized CR |
| Alert rules (×2) | `Orders API 5xx` + `health check failing` |
| Knowledge base (×6) | Runbooks uploaded to agent memory (data plane) |
| Subagents | `orchestrator-agent` + `triage-agent`; `issue-triager` when `GITHUB_REPO` is set |

> **Two phases:** Terraform deploys ARM resources; `post-provision.sh` deploys data-plane items (subagents, knowledge, response plan) that require audience `https://azuresre.dev`. Same split as Microsoft's [sreagent-templates](https://github.com/microsoft/sre-agent/tree/main/sreagent-templates).

## Scenario Guides

Each scenario has a standalone guide with diagram, exact run commands, expected output, and validation checks.

- [S1 guide: Detect and triage](docs/scenario-s1-detect-triage.md)
	- On-call incident response in Review mode. Trigger a rogue deploy, then watch the agent correlate 5xx telemetry with a missing change request and recommend rollback.
- [S2 guide: Autonomous remediation](docs/scenario-s2-autonomous-remediation.md)
	- Same incident path, but with High access and Automatic action mode so the agent performs rollback itself and posts a post-action summary.
- [S3 guide: Change issue triage](docs/scenario-s3-change-issue-triage.md)
	- Scheduled support workflow that classifies customer issues, links CR context, applies labels, and posts triage comments.
- [S4 guide: Platform reliability governance](docs/scenario-s4-platform-reliability-governance.md)
	- Platform team governance workflow that evaluates reliability guardrails and creates actionable backlog items to prevent repeat incidents.

