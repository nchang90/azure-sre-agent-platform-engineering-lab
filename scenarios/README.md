# Scenarios

- [S1 Detect & Triage](./s1-detect-triage/)
- [S2 Autonomous Remediation](./s2-autonomous-remediation/)
- [S3 Change Issue Triage](./s3-change-issue-triage/)
- [S4 Enterprise Guardrails](./s4-enterprise-guardrails/)
- [S5 PIM Elevation Audit & Alignment](./s5-pim-elevation-audit/README.md)

## Scenario steps and tfvars guidance

Any scenario can use any file in `infra/terraform/environments/*.tfvars`, or a new custom tfvars file you create, as long as it enables the scenario's required toggles. A matching backend file must exist at `infra/terraform/backend/<environment>.backend.tfvars`, then run `bash scripts/apply-extras.sh <environment>`.

`apply-extras.sh` reads the selected tfvars file and registers the matching recipe catalog:
- All environments upload every `.github/skills/*/SKILL.md` skill and every `knowledge-base/*.md` document.
- `deploy_apps = true` registers Container Apps subagents and response plans.
- `deploy_apps = false` registers AKS subagents and response plans.
- `tags.scenario = "s4"` adds the enterprise issue-triage subagent.

| Scenario | Recommended tfvars | Required apply-extras step | Optional step |
|---|---|---|---|
| S1 Detect and triage | N/A (uses `azd`/Bicep) | `azd env new s1-demo` then `azd provision` | `azd env get-values` |
| S2 Autonomous remediation | `environments/sbox.tfvars` | `bash scripts/apply-extras.sh sbox` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S3 AKS incident remediation | Any tfvars with `deploy_apps = false` | `bash scripts/apply-extras.sh <environment>` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S4 Guardrails/connectors | `environments/demo.tfvars` | `bash scripts/apply-extras.sh demo` | Configure GitHub in Azure SRE Agent portal (when running GitHub-enabled flows) |

For S2 with another environment such as `prod.tfvars`, keep the same S2-critical settings used by `sbox.tfvars`: `deploy_apps = true`, `access_level = "High"`, `enable_app_insights_connector = true`, `enable_log_analytics_connector = true`, and `enable_sev01_incident_filter = true`.
