# S6 — MCP Usage Monitoring & Governance

Persona: Platform Engineering / FinOps • Time: ~15 minutes • Entry point: Optional add-on

---

## Story
The platform team wants visibility into SRE Agent/MCP tool usage: which tools are most used, error rates, latency, and emerging anomalies. A weekly agent analyzes Log Analytics, produces a JSON + plaintext governance report, and optionally emails it to owners.

---

## How the Agent Handles It
| Step | What happens |
|------|--------------|
| Aggregate | Query workspace usage tables for last 7 days |
| Summarize | Top tools, error rates, p50/p95 latency |
| Detect | Spike hints comparing last 24h vs prior 6d |
| Report | JSON artifact + plaintext/email rollup |

---

## Prerequisites
- Log Analytics workspace collecting SRE Agent/MCP usage and errors (custom logs)
- Optional: Outlook connector configured for email

---

## Setup
1. Open `recipes/azmon-lawappinsights/agents/mcp-usage-governance-agent.yaml`.
2. Replace placeholders:
   - `REPLACE_WITH_WORKSPACE_ID`
   - `REPLACE_WITH_TOOL_USAGE_TABLE`, `REPLACE_WITH_ERROR_TABLE` (as applicable)
   - `REPLACE_WITH_CONNECTOR_ID`, `REPLACE_WITH_RECIPIENTS` (optional email)
3. Register the agent (portal or API). Suggested schedule: weekly.

---

## Run & Validate
- Trigger a manual run once to confirm outputs.
- Verify the JSON artifact contains top tools, error rates, and spike hints.
- If email enabled, confirm recipients receive the weekly report.

---

## Notes
- Adapt KQL field names to your actual schema.
- Start with simple spike heuristics; refine with your anomaly logic later.
- Treat as governance/observability only — no remediation actions are performed.
