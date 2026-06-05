# Change Lookup Tool

A FastAPI service that gives the SRE Agent and ServiceNow workflow context about
**Change Requests (CRs)**. In production it would proxy ServiceNow's
`/api/now/table/change_request`; in this lab it returns mock CR data.

## What it does

- Look up a CR by number (e.g. `CHG0030001`)
- Find the CR currently in its planned implementation window
- Find the CR linked to a specific Git commit (for unauthorized-change detection)
- Return risk, blast radius, rollback plan, and a suggested ServiceNow work-note hint

## Run locally

```bash
cd change-lookup
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --port 8010
```

## Endpoints

- `GET /health`
- `GET /changes` — list all CRs (filter: `?state=Implement`, `?risk=High`)
- `GET /changes/{cr}` — single CR
- `GET /changes/active/now` — the CR currently being implemented
- `GET /changes/by-commit/{sha}` — find CR linked to a commit

## Why it exists

This is the equivalent of AzureFriday's warranty tool, refocused on Change
Management. Instead of looking up a device's warranty status, it gives the SRE
Agent the active Change Request context whenever an alert fires — so the agent
can correlate a 5xx surge with a specific deploy, post a work note on the right
CR, and recommend rollback.

## Data shape

```json
{
  "number": "CHG0030001",
  "shortDescription": "Deploy orders-api v2.4 — pricing tier rollout",
  "state": "Implement",
  "type": "Standard",
  "risk": "Moderate",
  "linkedCommit": "abc123def456",
  "linkedPullRequest": "https://github.com/example/orders-api/pull/142",
  "blastRadius": "orders-api production, all regions",
  "rollbackPlan": "az containerapp update --revision-suffix prev",
  "serviceNowHint": "Update work_notes with App Insights link if 5xx > 5/min during the window."
}
```
