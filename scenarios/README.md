# Scenarios

- [S1 Detect & Triage](./s1-detect-triage/)
- [S2 Autonomous Remediation](./s2-autonomous-remediation/)
- [S3 Change Issue Triage](./s3-change-issue-triage/)
- [S4 Enterprise Guardrails](./s4-enterprise-guardrails/)
- [S5 PIM Elevation Audit & Alignment](./s5-pim-elevation-audit/README.md)

## Scenario steps and tfvars guidance

Any scenario can use any file in `infra/terraform/environments/*.tfvars`, or a new custom tfvars file you create. The table below shows recommended defaults only.

| Scenario | Recommended tfvars | Required post-provision step | Optional step |
|---|---|---|---|
| S1 Detect and triage | N/A (uses `azd`/Bicep) | `azd env new s1-demo` then `azd provision` | `azd env get-values` |
| S2 Autonomous remediation | Any existing tfvars (recommended: `environments/sbox.tfvars`) or a new custom tfvars | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S3 Change issue triage | `environments/demo.tfvars` or `environments/sbox.tfvars` | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (only if needed) |
| S4 Guardrails/connectors | `environments/demo.tfvars` | `bash scripts/post-provision.sh` | Configure GitHub in Azure SRE Agent portal (when running GitHub-enabled flows) |
