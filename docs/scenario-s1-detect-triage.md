# S1 - Detect and Triage

Persona: On-call / IT Ops

## Story

A developer ships a release straight to production with no change request and no peer review. The image is live and broken. The agent picks up the 5xx alert, finds no active CR, correlates timing with a new rogue revision, matches the Unauthorized Change runbook, and recommends rollback before on-call wakes up.

<img src="../images/story1.png" alt="detect and triage" width="600" />

## Scenario Diagram


## Run

```bash
bash scripts/break-app.sh
bash scripts/reset-app.sh
```

## Step by Step

1. Receives the Orders API 5xx Azure Monitor alert.
2. Delegates to triage-agent via orchestrator-agent.
3. Queries Log Analytics for recent 5xx traces.
4. Calls GET /health on orders-api and sees empty activeChangeRequest.
5. Queries change-lookup and finds no active CR in the deploy window.
6. Searches knowledge base and matches Unauthorized Change guidance.
7. Identifies rogue revision with az containerapp revision list.
8. Posts a structured incident summary with recommended rollback.

## Expected Output

Within 2-3 minutes, the portal run includes the offending rogue revision, missing CR evidence, and a rollback recommendation in Review mode.

## Validation

```bash
az containerapp revision list -n <orders-api-name> -g <rg> \
  -o table --query "[].{rev:name,active:properties.active,weight:properties.trafficWeight}"
azd env get-value AGENT_PORTAL_URL
```

## Knowledge Base

- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
- [http-500-errors.md](../knowledge-base/http-500-errors.md)