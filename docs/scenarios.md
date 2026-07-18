# Scenarios

Five progressive scenarios covering the full SRE agent lifecycle — from detection through enterprise-governed remediation.

| # | Scenario | Description |
|---|----------|-------------|
| S1 | [Detect & Triage](../scenarios/s1-detect-triage/README.md) | Trigger a 5xx incident and investigate in review mode. |
| S2 | [Autonomous Remediation](../scenarios/s2-autonomous-remediation/README.md) | Break the running app with a `curl` and watch the agent detect, investigate, and remediate — runtime only, no redeploy. |
| S3 | [Incident Root Cause Investigation](../scenarios/s3-incident-root-cause-investigation/README.md) | Investigate AKS regressions with GitHub repo evidence and HTTP trigger routing. |
| S4 | [Enterprise Guardrails and Connectors at Scale](../scenarios/s4-enterprise-guardrails/README.md) | Demonstrate governed ServiceNow, GitHub Enterprise, and observability workflows with tool permissions and controlled handoffs. |
| S5 | [PIM Elevation Audit & Alignment](../scenarios/s5-pim-elevation-audit/README.md) *(optional add-on)* | Audit Entra PIM activations, correlate Azure Activity, and classify alignment; email summary. |

## Scenario steps and tfvars guidance

See [scenarios/README.md](../scenarios/README.md) for detailed per-scenario steps and `tfvars` recommendations.
