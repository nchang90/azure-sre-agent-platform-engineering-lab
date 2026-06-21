<!-- Repo-level Copilot guidance for the Azure SRE Agent lab -->

# Azure SRE Agent Lab

This repository contains the Grubify sample app, Azure infrastructure, runbooks, and agent skills for incident response and issue triage.

## What to optimize for

- Keep changes small, safe, and reversible.
- Prefer existing runbooks, knowledge-base docs, and skill files over inventing new workflows.
- Preserve the lab’s incident response flow: detect, triage, correlate, remediate, and summarize.
- Use the Grubify architecture and incident templates when generating reports or GitHub issues.

## Key locations

- `skills/` — agent skills used by the SRE agent runtime.
- `.github/skills/` — Copilot-discoverable skills for this repository.
- `knowledge-base/` — runbooks, architecture notes, and issue templates.
- `recipes/azmon-lawappinsights/agents/` — agent configuration and handoff definitions.
- `scripts/post-provision.sh` — registers subagents, skills, response plans, and scheduled tasks with the agent data plane.

## When working on incidents

- Use `incident-orchestrator-coordination` for incident updates and delegation.
- Use `containerapps-500-diagnostics` for HTTP 500 and Container Apps investigations.
- Follow the structured incident report template when writing summaries or GitHub issues.

## Style guidance

- Be concise, explicit, and evidence-driven.
- Distinguish facts from hypotheses.
- Prefer safe mitigations first.
