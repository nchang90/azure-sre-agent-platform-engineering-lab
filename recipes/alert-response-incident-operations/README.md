# alert-response-incident-operations

Azure SRE Agent recipe for S3 AKS incident investigation.

S3 uses a three-agent Azure SRE Agent handoff chain:

1. `aks-triage-agent` investigates AKS logs, metrics, events, and changes.
2. It hands the shared context to `incident-summary-agent`.
3. Summary hands off to `incident-comms-agent`, which produces the final update
   for the originating ServiceNow incident workflow.

The `aks-critical-errors` Azure Monitor response plan still supplies AKS alert
context, but the demo flow starts when a ServiceNow incident workflow calls the
Azure SRE Agent HTTP trigger with the incident payload. S3 investigates Azure
Monitor and AKS evidence, then returns a diagnosis and report without executing
remediation.

## S3 deployment

```bash
bash scripts/apply-extras.sh demo
```
