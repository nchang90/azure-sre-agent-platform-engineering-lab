# alert-response-incident-operations

Azure SRE Agent recipe supplying a three-agent incident-investigation handoff
chain. Used by **S3** (AKS root-cause investigation) and **S4** (alert response
and incident operations).

The chain is the same in both; only the triage head differs:

```text
S3:  aks-triage-agent   -> incident-summary-agent -> incident-comms-agent
S4:  alert-investigator -> incident-summary-agent -> incident-comms-agent
```

1. The triage head investigates logs, metrics, events and recent changes —
   `aks-triage-agent` for AKS evidence, `alert-investigator` (from the
   `azmon-lawappinsights` recipe) for Azure Monitor alert evidence.
2. It hands the shared context to `incident-summary-agent`, which is runtime
   agnostic.
3. Summary hands off to `incident-comms-agent`, which produces the final update
   for the originating record — a ServiceNow incident in S3, an operator
   escalation in S4.

Every agent in the chain is read-only and must not claim a remediation was
performed. Connectors, skills, knowledge base and response plans come from the
`azmon-lawappinsights` recipe; this recipe contributes subagents only.

The demo flow starts when an operator opens a ServiceNow incident and the
agent's ServiceNow connector picks it up — a matching incident record is the
trigger, not the underlying AKS failure. Which response plan is registered
follows the connector: `aks-incidents` (ServiceNow) when
`enable_service_now_connector = true`, otherwise `aks-critical-errors`
(Azure Monitor). The agent's incident platform is a single setting, so only one
of the two is live at a time. S3 investigates Azure Monitor and AKS evidence,
then returns a diagnosis and report without executing remediation.

## Deployment

The chain is registered by scenario scope in `scripts/catalog.sh`:

```bash
bash scripts/apply-extras.sh demo   # scenario = s3
bash scripts/apply-extras.sh dev    # scenario = s4
```
