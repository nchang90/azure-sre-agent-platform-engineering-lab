# S5 - Infrastructure Resiliency Manager + Chaos Validation (Optional)

Persona: Platform Engineering / Reliability Engineering

## Story

After S1-S4 are in place, the team wants measurable resilience evidence, not just incident response. In this optional scenario, Azure Infrastructure Resiliency Manager is used as the resilience control plane to define goals, assess posture, and plan remediation. Azure Chaos Studio is then used as the drill engine for controlled fault injection in a non-production environment. Azure SRE Agent remains the operational response layer for detect, triage, and safe remediation decisions.

This scenario is intentionally controlled: limited blast radius, predefined rollback, strict stop criteria, and human-in-the-loop approvals.

## Safety First (Hard Requirements)

- **Run only in non-production subscriptions**.
- **Use a dedicated drill resource group** (or tagged target set) to constrain blast radius.
- **Start with one fault at a time** and short drill windows.
- **Define rollback before each run** (for example `bash scripts/reset-app.sh`).
- **Use explicit abort criteria** (for example sustained Sev1 or customer-impacting error rate).
- **Run with on-call visibility** and a named owner for the experiment window.

## Azure SRE Agent Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Goal-driven resilience** | Infrastructure Resiliency Manager evaluates posture against defined resilience goals |
| **Evidence-driven incident handling** | SRE Agent correlates drill window with logs, metrics, and active revision state |
| **Confidence and action mode** | In Review mode the agent recommends actions; in Automatic mode it can execute approved remediation |
| **Operational guardrails** | Drill boundaries are validated before and after experiment execution |
| **Cross-system traceability** | Experiment run ID and incident IDs are captured for postmortem evidence |

## Scenario Dependencies

- **Requires:** S1 baseline setup complete and incident alerting functional
- **Recommended:** S2/S4 completed so response posture and enterprise governance controls are already validated
- **Optional:** S3 if you want downstream issue-triage evidence from drill-generated incidents

## Lifecycle Flow

1. **Start Resilient:** define resilience scope and goals in Infrastructure Resiliency Manager.
2. **Get Resilient:** review posture gaps and prioritize recommendations.
3. **Stay Resilient:** run a controlled zone-down or service drill with Chaos Studio.
4. **Operate Safely:** validate SRE Agent triage quality, remediation decisions, and recovery timeline.

## Suggested Fault Progression

1. **Low risk:** increase HTTP latency briefly.
2. **Medium risk:** inject transient application error fault (short duration).
3. **Higher risk:** targeted pod/revision disruption with strict rollback gates.

Use only one fault type per run until behavior is well understood.

## Run

```bash
# Pre-check: confirm non-production context before any chaos run
az account show --query "{name:name, id:id, tenantId:tenantId}" -o table

# Verify agent portal target
azd env get-value AGENT_PORTAL_URL

# Baseline health before experiment
curl -s "$(azd env get-value ORDERS_API_URL)/health" | jq .

# Rollback command prepared and validated
bash scripts/reset-app.sh
```

Then execute the resiliency drill through Infrastructure Resiliency Manager (which orchestrates Chaos Studio fault actions) or run the equivalent Chaos Studio experiment directly with the same narrow target scope and short duration.

## Step by Step

1. Confirm you are in a non-production subscription and the intended resource group.
2. In Infrastructure Resiliency Manager, define or confirm the service scope and resiliency goal.
3. Review posture insights and select one recommendation or drill objective to validate.
4. Capture baseline health, error rate, and latency before the drill starts.
5. Start one controlled drill with a single fault and short duration.
6. Observe incident generation and SRE Agent triage behavior in the portal.
7. Validate output quality: root cause clues, confidence, and safe next action.
8. If stop criteria are hit, abort drill and run rollback immediately.
9. After completion, validate recovery and capture experiment ID, incident ID, and timeline evidence.

## Abort and Rollback Guardrails

Stop the drill immediately if any of the following are true:

- Sev1 impact is detected.
- Error rate exceeds your approved threshold for more than the allowed window.
- Customer-facing checkout path is unavailable.
- Agent recommendations conflict with policy constraints.

Rollback sequence:

1. Stop/abort drill in Infrastructure Resiliency Manager or Chaos Studio.
2. Restore service using `bash scripts/reset-app.sh`.
3. Re-check `GET /health`, active revision, and alert state.
4. Capture final verification artifacts in incident notes.

## Suggested Prompts

- *"Correlate the current incident with the active chaos experiment window and summarize blast radius."*
- *"Summarize this service group's resiliency goal and current posture gaps before we run the drill."*
- *"What signals indicate this is experiment-induced versus an unauthorized production change?"*
- *"Show the safest rollback command and explain why it is low risk."*
- *"List stop criteria status and tell me whether to continue or abort."*

## Expected Output

- Incident thread that references fault timing and affected component(s)
- Resiliency posture context (goal, gap, and recommendation) linked to the drill objective
- Structured triage summary with confidence and recommended/automatic action behavior
- Recovery confirmation after rollback
- Post-run evidence package: experiment ID, incident ID, timeline, and validation checks

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
