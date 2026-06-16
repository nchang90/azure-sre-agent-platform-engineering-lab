# S1 - Incident Response Across Azure Monitor

Persona: On-call / IT Ops

## Story

A developer ships a release straight to production with no change request and no peer review. The image is live and broken. The Azure Monitor alert fires automatically — the agent picks it up, triages the severity, queries Log Analytics for 5xx error patterns, correlates with Azure Monitor metrics and deployment history, pinpoints the root cause at the source file level, submits a fix PR, and resolves the alert — all before on-call wakes up. The session is saved so the next similar incident is handled faster.

<img src="../images/story1.png" alt="detect and triage" width="600" />

## How the SRE Agent Handles It

| Step | What happens |
|------|-------------|
| **Azure Monitor alert fires** | Agent picks it up automatically via Incident Response Plan — no human trigger needed |
| **Agent triages** | Classifies severity, identifies affected service, plans investigation |
| **Pulls Log Analytics logs** | Runs KQL queries through Log Analytics — 5xx counts, error patterns, spike timing |
| **Queries Azure Monitor** | Correlates with metrics, traces, and deployment history |
| **Searches source code** | Finds the root cause at file:line level in the repository |
| **Creates fix PR + resolves alert** | Submits PR with proposed code change, resolves the Azure Monitor incident |
| **Remembers for next time** | Session insights saved — next similar incident is faster |

## Azure SRE Agent Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Incident Response Plan** | The pre-configured response plan routes the Azure Monitor `Orders API 5xx` alert to `orchestrator-agent` automatically — no human needed to start the thread |
| **Subagents** | `orchestrator-agent` normalises the alert into an `IncidentContext` and delegates deep investigation to `triage-agent` |
| **Log Analytics connector** | `triage-agent` queries `ContainerAppConsoleLogs_CL` via `QueryLogAnalyticsByWorkspaceId` to find the error spike and error patterns |
| **Azure Monitor metrics** | Agent correlates 5xx spike with CPU, memory, request latency, and deployment timeline metrics |
| **Knowledge base (memory)** | Agent searches uploaded runbooks and matches the _Unauthorized Change_ guidance in `change-management-runbook.md` |
| **Source code search** | Agent identifies the offending file and line number in the repository and proposes a targeted fix |
| **PR creation** | Agent submits a fix PR with the proposed code change for human review |
| **Alert resolution** | Agent resolves the Azure Monitor alert once the fix PR is submitted |
| **Session insights** | Findings are saved so the next similar incident skips re-discovery steps |

## Scenario Dependencies

- **Requires:** none — this is the entry point for the lab
- **Unlocks:** S2 (re-run with higher trust to act autonomously), S3 (customer issues reference this incident's CHG numbers), S4 (enterprise controls walkthrough uses this incident as the governed starting point)

## Run

```bash
bash scripts/break-app.sh
bash scripts/reset-app.sh
```

## Step by Step

1. `break-app.sh` ships a rogue revision directly to Container Apps with no CR.
2. The `Orders API 5xx` Azure Monitor alert fires within ~1 minute.
3. The Incident Response Plan routes the alert to `orchestrator-agent`.
4. `orchestrator-agent` normalises the alert into an `IncidentContext` (service, symptom, time window, environment) and classifies severity.
5. `orchestrator-agent` delegates to `triage-agent` for technical investigation.
6. `triage-agent` queries Log Analytics (`ContainerAppConsoleLogs_CL`) for the 5xx spike and error patterns.
7. `triage-agent` queries Azure Monitor metrics — CPU, memory, latency, and deployment history — and correlates timing with the rogue revision.
8. `triage-agent` calls `GET /health` on orders-api and reads `activeChangeRequest: ""` (empty string).
9. `triage-agent` queries `change-lookup /changes/active/now` and confirms no active CR.
10. `triage-agent` searches the knowledge base and matches the Unauthorized Change runbook.
11. `triage-agent` runs `az containerapp revision list` and identifies the rogue revision.
12. `triage-agent` searches the source repository and identifies the root cause at file:line level.
13. `orchestrator-agent` submits a fix PR with the proposed code change.
14. `orchestrator-agent` resolves the Azure Monitor alert and posts a structured incident summary.
15. Session insights are saved — the root cause, KQL queries, and fix pattern are stored for future incidents.

## Portal Steps

1. Open [sre.azure.com](https://sre.azure.com) and navigate to your agent.
2. Go to **Incidents** — a new incident thread appears within ~2 minutes of `break-app.sh`.
3. Open the incident thread and watch the agent work through steps 3–15 in real time.
4. Inspect the **Artifacts** panel: KQL query used, metrics snapshot, revision list output, and source file reference.
5. The final message shows the fix PR link, the resolved alert, and the saved session insight.

## Suggested Prompts

After the agent posts its finding, continue the thread to deepen your understanding:

- *"Show me the KQL query you used to find the 5xx spike"*
- *"Which runbook matched and what were the key signals?"*
- *"What was the root cause at the source level?"*
- *"Why did you create a PR instead of deploying directly?"*
- *"What did you save for next time?"*

## Expected Output

Within 2-3 minutes, the portal incident thread includes:
- The offending rogue revision name
- Evidence of missing CR (`change-lookup` returned no active CR)
- The KQL error trace and Azure Monitor metrics correlation
- The root cause file and line number in the repository
- A submitted fix PR link
- The Azure Monitor alert marked as resolved
- A session insight entry for future incidents

## Validation

```bash
az containerapp revision list -n <orders-api-name> -g <rg> \
  -o table --query "[].{rev:name,active:properties.active,weight:properties.trafficWeight}"
azd env get-value AGENT_PORTAL_URL
```

## Knowledge Base

- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
- [http-500-errors.md](../knowledge-base/http-500-errors.md)
- [orders-architecture.md](../knowledge-base/orders-architecture.md)
