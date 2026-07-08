# S5 — Security Incident Investigation

Persona: SecOps / SOC • Time: ~20 minutes • Entry point: Add-on

---

## Story
A high-severity Microsoft Sentinel incident is created. The agent pulls the incident, gathers linked alerts and entities, builds a timeline and MITRE tactics map, and produces a concise report with recommended next steps.

---

## How the Agent Handles It
| Step | What happens |
|------|--------------|
| Pull | Query Sentinel incidents (or a given Incident Id) |
| Correlate | Join related alerts and entities; build timeline |
| Analyze | Group by tactics/severity; highlight blast radius |
| Report | JSON + plaintext summary with recommended actions |

---

## Prerequisites
- Sentinel-enabled Log Analytics workspace with SecurityIncident/SecurityAlert tables
- Optional M365 Defender/AAD logs for enrichment

---

## Setup
1. Open `recipes/azmon-lawappinsights/agents/security-incident-investigator.yaml`.
2. Replace `REPLACE_WITH_WORKSPACE_ID`.
3. Register the agent (portal or API). Optional input: Incident Id.

---

## Run & Validate
- Trigger a manual run for a known incident or last 24h.
- Verify the JSON artifact (alerts, entities, timeline) and plaintext summary.

---

## Notes
- Adapt KQL fields/tables to your workspace.
- Treat outputs as guidance; no automated remediation performed.
