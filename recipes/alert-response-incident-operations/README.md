# alert-response-incident-operations

Azure SRE Agent recipe for S3 AKS incident response.

S3 uses a three-agent Azure SRE Agent handoff chain:

1. `aks-triage-agent` investigates AKS logs, metrics, events, and changes.
2. It hands the shared context to `incident-summary-agent`.
3. Summary hands off to `incident-comms-agent`, which produces the final update
   for the active ServiceNow incident.

The ServiceNow response plan is maintained under
`recipes/azmon-lawappinsights/incident-platforms/servicenow/`. S3 does not
create another incident, execute remediation, or update another system.

## S3 deployment

```bash
bash scripts/apply-extras.sh demo
```
