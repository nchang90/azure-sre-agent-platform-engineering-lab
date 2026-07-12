from datetime import datetime, timedelta
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Change Request Lookup Service", version="1.0.0")

NOW = datetime.utcnow()

# Mock ServiceNow Change Requests. In a real deployment this would proxy to /api/now/table/change_request.
CHANGE_REQUESTS = {
    "CHG0030001": {
        "number": "CHG0030001",
        "shortDescription": "Deploy orders-api v2.4 — pricing tier rollout",
        "state": "Implement",
        "type": "Standard",
        "risk": "Moderate",
        "assignmentGroup": "Orders Platform",
        "assignedTo": "alex.morgan@example.com",
        "plannedStart": (NOW - timedelta(minutes=20)).isoformat() + "Z",
        "plannedEnd":   (NOW + timedelta(minutes=40)).isoformat() + "Z",
        "linkedCommit": "abc123def456",
        "linkedPullRequest": "https://github.com/example/orders-api/pull/142",
        "blastRadius": "orders-api production, all regions",
        "rollbackPlan": "az containerapp update --revision-suffix prev",
        "serviceNowHint": "Update work_notes with App Insights link if 5xx > 5/min during the window."
    },
    "CHG0030002": {
        "number": "CHG0030002",
        "shortDescription": "Database index update on orders schema",
        "state": "Scheduled",
        "type": "Normal",
        "risk": "Low",
        "assignmentGroup": "Data Platform",
        "assignedTo": "jordan.rivera@example.com",
        "plannedStart": (NOW + timedelta(hours=6)).isoformat() + "Z",
        "plannedEnd":   (NOW + timedelta(hours=7)).isoformat() + "Z",
        "linkedCommit": None,
        "linkedPullRequest": None,
        "blastRadius": "orders DB read replicas",
        "rollbackPlan": "DROP INDEX IF EXISTS",
        "serviceNowHint": "No SRE action expected — pre-approved standard change."
    },
    "CHG0030003": {
        "number": "CHG0030003",
        "shortDescription": "Emergency hotfix — null reference in checkout",
        "state": "Closed",
        "type": "Emergency",
        "risk": "High",
        "assignmentGroup": "Orders Platform",
        "assignedTo": "sam.kim@example.com",
        "plannedStart": (NOW - timedelta(days=1)).isoformat() + "Z",
        "plannedEnd":   (NOW - timedelta(days=1, hours=-1)).isoformat() + "Z",
        "linkedCommit": "9f8e7d6c5b4a",
        "linkedPullRequest": "https://github.com/example/orders-api/pull/138",
        "blastRadius": "orders-api production",
        "rollbackPlan": "Revert PR #138",
        "serviceNowHint": "Closed successful — reference for PIR template."
    }
}


@app.get("/")
def root():
    return {
        "service": "change-lookup",
        "version": "1.0.0",
        "message": "Lookup ServiceNow change requests for SRE Agent investigations"
    }


@app.get("/health")
def health():
    return {"status": "healthy", "service": "change-lookup"}


@app.get("/changes/{cr_number}")
def get_change(cr_number: str):
    cr = CHANGE_REQUESTS.get(cr_number)
    if cr is None:
        raise HTTPException(status_code=404, detail={"error": f"Change request {cr_number} not found"})
    return cr


@app.get("/changes")
def list_changes(state: str | None = None, risk: str | None = None):
    changes = list(CHANGE_REQUESTS.values())
    if state:
        changes = [c for c in changes if c["state"].lower() == state.lower()]
    if risk:
        changes = [c for c in changes if c["risk"].lower() == risk.lower()]
    return {"count": len(changes), "changes": changes}


@app.get("/changes/active/now")
def active_change():
    """Return the change currently in its planned window (state=Implement)."""
    for cr in CHANGE_REQUESTS.values():
        if cr["state"] == "Implement":
            return cr
    raise HTTPException(status_code=404, detail={"error": "No active change request"})


@app.get("/changes/by-commit/{commit_sha}")
def get_change_by_commit(commit_sha: str):
    for cr in CHANGE_REQUESTS.values():
        if cr.get("linkedCommit") and cr["linkedCommit"].startswith(commit_sha):
            return cr
    raise HTTPException(status_code=404, detail={"error": f"No change request linked to commit {commit_sha}"})
