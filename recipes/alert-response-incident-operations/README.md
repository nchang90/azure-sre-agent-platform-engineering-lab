# alert-response-incident-operations

Azure SRE Agent recipe for S3 AKS incident response.

S3 uses a three-agent Azure SRE Agent handoff chain:

1. `aks-triage-agent` investigates AKS logs, metrics, events, and changes.
2. It hands the shared context to `incident-summary-agent`.
3. Summary hands off to `incident-comms-agent`, which produces the final update
   for the active Azure Monitor incident.

The `aks-critical-errors` Azure Monitor response plan handles Sev0 and Sev1
alerts whose title contains `AKS`. The S3 crash-loop simulation raises a Sev1
alert, which creates an incident and starts the three-agent investigation.
The deployment workflow also adds the simulation context to the newest active
ServiceNow incident whose short description contains `AKS`. S3 investigates
and summarizes the Azure Monitor incident without executing remediation.

## S3 deployment

```bash
bash scripts/apply-extras.sh demo
```
