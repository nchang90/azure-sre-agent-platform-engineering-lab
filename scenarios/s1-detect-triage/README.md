# S1 — Incident Detection & Triage

**Persona:** On-call / IT Ops
**Time to complete:** ~15 minutes
**Entry point:** This is the starting scenario — run it first.

---

## Story

A developer ships a release straight to production with no change request and no peer review. The image is live and broken. The Azure Monitor alert fires automatically — the agent picks it up, triages the severity, queries Log Analytics for 5xx error patterns, correlates with Azure Monitor metrics and deployment history, pinpoints the root cause at the source file level, submits a fix PR, and resolves the alert — all before on-call wakes up. The session is saved so the next similar incident is handled faster.

<img src="../images/story1.png" alt="detect and triage" width="600" />

---

## How the Agent Handles It

| Step | What happens |
|------|-------------|
| **Alert fires** | Agent picks up the Azure Monitor alert automatically via Incident Response Plan — no human trigger needed |
| **Triage** | Classifies severity, identifies affected service, plans investigation |
| **Log Analytics** | Runs KQL queries — 5xx counts, error patterns, spike timing |
| **Azure Monitor** | Correlates with metrics, traces, and deployment history |
| **Source search** | Finds the root cause at `file:line` level in the repository |
| **Fix PR + alert resolve** | Submits PR with proposed code change, resolves the incident |
| **Session insights** | Findings saved — next similar incident skips re-discovery |

---

## Key Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Incident Response Plan** | Routes the `Orders API 5xx` alert to `orchestrator-agent` automatically |
| **Subagents** | `orchestrator-agent` normalizes the alert into an `IncidentContext` and delegates to `triage-agent` |
| **Log Analytics connector** | `triage-agent` queries `ContainerAppConsoleLogs_CL` via `QueryLogAnalyticsByWorkspaceId` |
| **Azure Monitor metrics** | Agent correlates 5xx spike with CPU, memory, latency, and deployment timeline |
| **Knowledge base** | Agent searches uploaded runbooks and matches the _Unauthorized Change_ guidance |
| **Source code search** | Agent identifies the offending file and line number and proposes a targeted fix |
| **PR creation** | Agent submits a fix PR for human review |
| **Alert resolution** | Agent resolves the Azure Monitor alert once the fix PR is submitted |
| **Session insights** | Findings saved so future incidents skip re-discovery steps |

---

## Scenario Map

| Relationship | Scenario |
|-------------|----------|
| **Prerequisites** | None — this is the entry point |
| **Unlocks** | [S2](./scenario-s2-autonomous-remediation.md) — break the running app at runtime and watch the agent remediate |
| **Unlocks** | [S3](./scenario-s3-change-issue-triage.md) — customer issues reference this incident's CHG numbers |
| **Unlocks** | [S4](./scenario-s4-enterprise-guardrails-connectors.md) — enterprise controls walkthrough uses this incident as the governed starting point |

---

## Run

```bash
bash scripts/break-app.sh
```

To restore afterward:

```bash
# If runtime 5xx simulation mode was used
APP_URL="$(cd infra/terraform && terraform output -raw orders_api_url)"
curl -X POST "$APP_URL/api/simulate/reset"
curl -X POST "$APP_URL/api/simulate/clear-cr"

# If fallback image-break mode was used, restore a working image
az containerapp update -g <rg> -n orders-api --image <working-image>
```

---

## Step by Step

1. The `break-app.sh` script is no longer available (chaos monkey support has been removed).
5. The `Orders API 5xx` Azure Monitor alert evaluates on a 5 minute window and typically appears within a few minutes.
6. The Incident Response Plan routes the alert to `orchestrator-agent`.
7. `orchestrator-agent` normalizes the alert into an `IncidentContext` (service, symptom, time window, environment) and classifies severity.
8. `orchestrator-agent` delegates to `triage-agent` for technical investigation.
9. `triage-agent` queries Log Analytics / Application Insights request data for the `5xx` spike and error patterns.
10. `triage-agent` queries Azure Monitor metrics — CPU, memory, latency, and deployment history — and correlates timing with the rogue revision or simulated change window.
11. If the app is reachable, `triage-agent` calls `GET /health` on orders-api and inspects `activeChangeRequest`.
12. `triage-agent` queries `change-lookup /changes/active/now` and confirms whether there was an active CR.
13. `triage-agent` searches the knowledge base and matches the Unauthorized Change runbook.
14. `triage-agent` runs `az containerapp revision list` and identifies the rogue revision.
15. `triage-agent` searches the source repository and identifies the root cause at `file:line` level.
16. `orchestrator-agent` submits a fix PR with the proposed code change.
17. `orchestrator-agent` resolves the Azure Monitor alert and posts a structured incident summary.
18. Session insights are saved — the root cause, KQL queries, and fix pattern are stored for future incidents.

---

## Portal Steps

1. Open [sre.azure.com](https://sre.azure.com) and navigate to your agent.
2. Go to **Incidents** — a new incident thread should appear after the alert evaluation window completes, typically within ~5 to 10 minutes of running `break-app.sh`.
3. Open the incident thread and watch the agent work through steps 3–15 in real time.
4. Inspect the **Artifacts** panel: KQL query used, metrics snapshot, revision list output, and source file reference.
5. The final message shows the fix PR link, the resolved alert, and the saved session insight.

---

## Suggested Prompts

After the agent posts its findings, continue the thread to go deeper:

- *"Show me the KQL query you used to find the 5xx spike"*
- *"Which runbook matched and what were the key signals?"*
- *"What was the root cause at the source level?"*
- *"Why did you create a PR instead of deploying directly?"*
- *"What did you save for next time?"*

---

## Expected Output

After the alert window completes, the portal incident thread includes:

- The offending rogue revision name
- Evidence of missing CR (`change-lookup` returned no active CR)
- The KQL error trace and Azure Monitor metrics correlation
- The root cause file and line number in the repository
- A submitted fix PR link
- The Azure Monitor alert marked as resolved
- A session insight entry for future incidents

---

## Validation

```bash
az containerapp revision list -n <orders-api-name> -g <rg> \
  -o table --query "[].{rev:name,active:properties.active,weight:properties.trafficWeight}"

azd env get-value AGENT_PORTAL_URL
```

---

## Knowledge Base

- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
- [http-500-errors.md](../knowledge-base/http-500-errors.md)
- [orders-architecture.md](../knowledge-base/orders-architecture.md)
