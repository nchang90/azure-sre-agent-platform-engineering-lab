# S5 — PIM Elevation Audit & Alignment

Persona: Security/Compliance Ops  •  Time: ~15 minutes  •  Entry point: Optional add-on

---

## Story
A user elevates to a privileged role with a brief justification. The agent runs daily, discovers PIM activations, builds each activation window, correlates actual Azure Activity performed during elevation, and classifies whether actions align with the stated justification. A JSON report and an email summary are produced; misalignment is flagged for review.

---

## How the Agent Handles It
| Step | What happens |
|------|--------------|
| Discover | Query Entra AuditLogs for PIM activation requests/completions and extract justification |
| Window | Construct activation start/end and a ±5m buffer |
| Correlate | Query AzureActivity for operations by the elevated user within each window |
| Classify | Keyword-match justification vs. operations (Aligned/Partial/NotAligned) |
| Report | Emit JSON + plaintext; email summary via connector |

---

## Prerequisites
- Entra PIM enabled; AuditLogs exported to Log Analytics
- Azure Activity exported to the same Log Analytics workspace
- Outlook connector configured for the SRE Agent

---

## Setup
1. Open `recipes/azmon-lawappinsights/agents/pim-elevation-agent.yaml`.
2. Replace:
   - `REPLACE_WITH_WORKSPACE_ID` with your Log Analytics workspace ID
   - `REPLACE_WITH_CONNECTOR_ID` and `REPLACE_WITH_RECIPIENT_EMAILS`
3. Register the agent (portal or API). Example API path used by this repo:
   - `PUT /api/v2/extendedAgent/agents/PIM-Elevation` with the converted JSON body.

> Tip: Keep this agent disabled in lower environments without PIM logs.

---

## Run & Validate
- Wait for the daily schedule or manually trigger the agent.
- Perform a short PIM elevation with a clear justification (e.g., "restore storage backup").
- Verify:
  - JSON summary artifact present in the agent run
  - Email received with alignment verdict
  - Any NotAligned findings highlighted

---

## Expected Output
- JSON: `runUtc`, analysis window, and per-activation entries (user, role, scope, justification, sample activities, verdict, notes)
- Email: Plaintext rollup with per-activation verdicts; Non-aligned activities called out in the header

---

## Notes
- Extend keyword rules as needed for your environment
- Treat reports as advisory; no remediation actions are performed
