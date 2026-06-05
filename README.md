# Azure SRE Agent — Platform Engineering Lab

A hands-on lab for Azure SRE Agent. Four scenarios that build on each other. Designed for platform engineering teams to experience the agent's capabilities in incident response, autonomous remediation, change triage, and reliability governance. Deploys a sample monitored app with an SRE Agent that has RBAC permissions to take action and learn from outcomes.

## Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | `brew install azure-cli` or [guide](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| Terraform 1.5+ | `brew install terraform` or [guide](https://developer.hashicorp.com/terraform/install) |

## Quick Start



> **Cloud Shell:** data-plane items (subagents) need `az login --scope "https://azuresre.dev/.default"`, or apply later with `bash scripts/post-provision.sh --retry`.

## Deployment

This repo deploys automatically with GitHub Actions using [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

- Triggered by manual run (`workflow_dispatch`) only.
- Supports manual inputs: `run_plan` and `run_apply` (both default to true).
- Logs in to Azure using the `AZURE_CREDENTIALS` repository secret.
- Runs `terraform -chdir=infra init`, `terraform -chdir=infra plan -out=tfplan -var-file=terraform.tfvars`, then `terraform -chdir=infra apply -auto-approve tfplan`.
- Runs `bash scripts/post-provision.sh` after Terraform to configure data-plane artifacts.

To tear down the lab, use [`.github/workflows/destroy.yml`](.github/workflows/destroy.yml): it runs daily at 21:00 UTC and can also be run manually (manual runs require `DESTROY` in `confirm_destroy`).

Set the `AZURE_CREDENTIALS` secret in your repository before relying on CI deployment.

## Scenarios

One storyline: an incident breaks the app, the agent remediates it, the next morning it triages customer fallout, and then the platform team closes the loop with governance guardrails. Each scenario can stand alone but builds on the one before it.

| Scenario | Persona | Trigger | What the agent does | Key concepts learned | Depends on |
|---|---|---|---|---|---|
| [S1 — Detect & triage](docs/scenario-s1-detect-triage.md) | On-call / IT Ops | `bash scripts/break-app.sh` | Picks up the 5xx alert, correlates a rogue deploy, finds no change request, recommends a rollback (Review mode) | Incident Response Plan, subagents, Log Analytics connector, knowledge base, Review mode | — |
| [S2 — Autonomous remediation](docs/scenario-s2-autonomous-remediation.md) | Platform / SRE | Re-run S1 in `High` / `Automatic` mode | Acts on its own — rolls the bad revision back without waiting for a human, posts a post-action summary | Access levels, Automatic action mode, `RunAzCliWriteCommands`, agent memory | S1 |
| [S3 — Change issue triage](docs/scenario-s3-change-issue-triage.md) | Support / Automation | `bash scripts/create-sample-issues.sh OWNER/REPO` | Reviews customer issues, links them to change requests, classifies, posts triage comments | Scheduled tasks, GitHub connector, issue-triager subagent, idempotent triage | S1 or S2 |
| [S4 — Platform reliability governance](docs/scenario-s4-platform-reliability-governance.md) | Platform Engineering | Chat: *"Run a governance review for orders-api"* | Recalls S1–S3 incident memory, evaluates reliability guardrails, scores risk, creates backlog issues to prevent recurrence | Memory and learning, deep context, `ExecutePythonCode`, proactive mode, GitHub issue creation | S1–S3 recommended |

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

Each scenario has a standalone guide with flow diagram, exact run commands, expected output, portal steps, suggested prompts, and validation checks. Each guide also lists the Azure SRE Agent concepts it demonstrates and its dependencies on other scenarios.

- [S1 guide: Detect and triage](docs/scenario-s1-detect-triage.md)
	- On-call incident response in Review mode. Trigger a rogue deploy, watch the agent correlate 5xx telemetry with a missing change request and recommend rollback. Teaches: Incident Response Plans, subagents, Log Analytics connector, knowledge base retrieval.
- [S2 guide: Autonomous remediation](docs/scenario-s2-autonomous-remediation.md)
	- Same incident path, but with High access and Automatic action mode so the agent performs rollback itself and posts a post-action summary. Teaches: access levels, automatic action mode, write permissions, agent memory.
- [S3 guide: Change issue triage](docs/scenario-s3-change-issue-triage.md)
	- Scheduled support workflow that classifies customer issues, links CR context, applies labels, and posts triage comments. Teaches: scheduled tasks, GitHub connector, issue-triager subagent, idempotent triage.
- [S4 guide: Platform reliability governance](docs/scenario-s4-platform-reliability-governance.md)
	- Platform team governance workflow that evaluates reliability guardrails using incident memory from S1–S3 and creates actionable backlog items to prevent repeat incidents. Teaches: memory and learning, deep context, proactive mode, Python code execution.

