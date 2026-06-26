# Agent Set Overview

This folder contains both core and optional subagents.

## Core (registered by default)

- `orchestrator-agent.yaml`
- `triage-agent.yaml`
- `issue-triager.yaml`

These are used by the main lab paths (S1, S3, and S4).

## Optional (registered only when related automations are enabled)

- `alert-investigator.yaml`

These are only needed for optional Azure Monitor automations like:

- Sev0/Sev1 incident filter (`enable_sev01_incident_filter`)
- Daily health check task (`enable_daily_health_check`)

The post-provision script handles this automatically.
