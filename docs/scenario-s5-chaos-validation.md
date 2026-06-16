# S5 - Infrastructure Resiliency Manager + Chaos Validation (Optional)

Persona: Platform Engineering / Reliability Engineering

## Story

After S1-S4 are in place, the team wants measurable resilience evidence, not just incident response. Azure Infrastructure Resiliency Manager (public preview) is the control plane: it groups resources into Service Groups, assigns zone-failure tolerance goals, surfaces Advisor-powered recommendations, and drives Availability Zone Failure Drills through Chaos Studio. Azure SRE Agent acts as the operational response layer — it detects incidents triggered by the drill, triages them, and makes safe remediation decisions. Together they close the loop between resilience planning and operational readiness.

This scenario is intentionally controlled: limited blast radius, predefined rollback, strict stop criteria, and human-in-the-loop approvals.

## Safety First (Hard Requirements)

- **Run only in non-production subscriptions.**
- **Use a dedicated drill resource group** (or tagged target set) to constrain blast radius.
- **Start with one fault at a time** and short drill windows.
- **Define rollback before each run** (`bash scripts/reset-app.sh`).
- **Use explicit abort criteria** (e.g. sustained Sev1 or customer-impacting error rate).
- **Run with on-call visibility** and a named owner for the experiment window.

## Azure Infrastructure Resiliency Manager Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Service Groups** | Resources are grouped by application boundary (across resource groups or by tag) to define the drill scope |
| **Goal-Driven Resiliency Posture** | A zone-failure tolerance goal is assigned to the Service Group — the dashboard shows which resources are compliant vs. at risk |
| **Resiliency Agent** | Embedded AI assistant that analyzes posture gaps, recommends specific fixes, and generates IaC (ARM, Bicep, or Terraform) to remediate them |
| **Actionable Recommendations** | Azure Advisor-powered guidance with implementation steps, cost indicators (High/Medium/Low), and impacted resource details |
| **Availability Zone Failure Drill** | Chaos Studio-backed simulation that shuts down VMs in a target zone, forces database failover, and stops AKS node pools — fault actions are determined automatically by resource type |
| **Recovery Orchestration** | Full-cycle simulation: fault injection → failover → reprotection → failback, measuring maximum potential downtime |
| **Real-Time Health Monitoring** | Azure Monitor dashboard tracks resource health during the drill; results, notes, and attestations are logged for compliance |

## Azure SRE Agent Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Evidence-driven incident handling** | SRE Agent correlates the drill window with logs, metrics, and active revision state to distinguish drill-induced faults from real incidents |
| **Confidence and action mode** | In Review mode the agent recommends actions; in Automatic mode it can execute approved remediation |
| **Operational guardrails** | Drill boundaries are validated before and after experiment execution |
| **Cross-system traceability** | Experiment run ID and incident IDs are captured together for postmortem evidence |

## Scenario Dependencies

- **Requires:** S1 baseline setup complete and incident alerting functional
- **Recommended:** S2/S4 completed so response posture and enterprise governance controls are already validated
- **Optional:** S3 if you want downstream issue-triage evidence from drill-generated incidents

## Three-Phase Journey

| Phase | What happens |
|-------|-------------|
| **Start Resilient** | Define the Service Group scope and assign a zone-failure tolerance goal |
| **Get Resilient** | Review posture gaps and Resiliency Agent recommendations; optionally generate Bicep/Terraform fixes |
| **Stay Resilient** | Run an Availability Zone Failure Drill and observe SRE Agent triage and recovery |

## Run

```bash
# Pre-check: confirm non-production context before any chaos run
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table

# Verify agent portal target
azd env get-value AGENT_PORTAL_URL

# Baseline health before drill
curl -s "$(azd env get-value ORDERS_API_URL)/health" | jq .

# Rollback command — prepare and validate before starting
bash scripts/reset-app.sh
```

## Step by Step

### Phase 1 — Start Resilient
1. Open Infrastructure Resiliency Manager in the Azure portal.
2. Create a **Service Group** scoped to the orders-api resource group (or use tag-based targeting).
3. Assign a **zone-failure tolerance goal** to the Service Group.
4. Review the posture dashboard — identify which resources are compliant vs. at risk.

### Phase 2 — Get Resilient
5. Open the **Resiliency Agent** and ask it to analyze posture gaps for the Service Group.
6. Review **Actionable Recommendations** (Advisor-powered) — note cost indicators and impacted resources.
7. Optionally request IaC output (Bicep or Terraform) from the Resiliency Agent to address a gap.

### Phase 3 — Stay Resilient (Drill)
8. Confirm you are in a non-production subscription and the intended resource group.
9. Capture baseline health, error rate, and latency before the drill starts.
10. Start one **Availability Zone Failure Drill** targeting a single zone with a short duration.
11. Infrastructure Resiliency Manager triggers Chaos Studio fault actions automatically (VM shutdown, DB failover, AKS node pool stop) based on resource type.
12. Observe the **Real-Time Health Monitoring** dashboard in Azure Monitor.
13. Watch the SRE Agent detect the drill-generated incident and triage it in the agent portal.
14. If stop criteria are hit, abort the drill immediately and run rollback.
15. After completion, observe **Recovery Orchestration** (failback sequence) and validate recovery.
16. Capture experiment run ID, incident ID, and timeline for postmortem evidence.

## Suggested Fault Progression

1. **Low risk:** increase HTTP latency briefly (no zone impact).
2. **Medium risk:** single Availability Zone Failure Drill — VM shutdown only, short window.
3. **Higher risk:** full Recovery Orchestration cycle — fault injection → failover → reprotection → failback.

Run only one fault type per session until behavior is well understood.

## Abort and Rollback Guardrails

Stop the drill immediately if any of the following are true:
- Sev1 impact is detected.
- Error rate exceeds your approved threshold for more than the allowed window.
- Customer-facing checkout path is unavailable.
- Agent recommendations conflict with policy constraints.

Rollback sequence:
1. Abort the drill in Infrastructure Resiliency Manager or Chaos Studio.
2. Restore service using `bash scripts/reset-app.sh`.
3. Re-check `GET /health`, active revision, and alert state.
4. Capture final verification artifacts in incident notes.

## Portal Steps

1. Open Infrastructure Resiliency Manager → confirm Service Group and goal are configured.
2. Review posture insights and chat with the Resiliency Agent for gap analysis.
3. Start the Availability Zone Failure Drill — observe real-time health dashboard.
4. Open [sre.azure.com](https://sre.azure.com) → **Incidents** — watch the SRE Agent triage the drill-generated incident.
5. After recovery, open the drill history in Infrastructure Resiliency Manager to view attestation log.

## Suggested Prompts

- *"Correlate the current incident with the active chaos experiment window and summarize blast radius."*
- *"Summarize this Service Group's resiliency goal and current posture gaps before we run the drill."*
- *"What signals indicate this is drill-induced versus an unauthorized production change?"*
- *"Show the safest rollback command and explain why it is low risk."*
- *"List stop criteria status and tell me whether to continue or abort."*

## Expected Output

- Posture dashboard showing Service Group goal compliance before and after the drill
- Resiliency Agent recommendations with IaC output for at least one gap
- Incident thread in the SRE Agent portal that references fault timing and affected component(s)
- Recovery Orchestration completion log (failover → reprotection → failback)
- Post-run evidence package: experiment run ID, incident ID, timeline, attestation log, and validation checks

## Validation

```bash
# Validate API health after rollback
curl -s "$(azd env get-value ORDERS_API_URL)/health" | jq .

# Validate active revision traffic state
az containerapp revision list -n <orders-api-name> -g <rg> \
  -o table --query "[].{rev:name,active:properties.active,weight:properties.trafficWeight}"
```

## Knowledge Base

- [http-500-errors.md](../knowledge-base/http-500-errors.md)
- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
- [incident-report-template.md](../knowledge-base/incident-report-template.md)
- [on-call-handoff.md](../knowledge-base/on-call-handoff.md)
