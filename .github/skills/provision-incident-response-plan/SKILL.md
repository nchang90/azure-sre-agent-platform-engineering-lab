---
name: provision-incident-response-plan
description: Create or recreate the orders-api health incident response plan ARM resource. Use when the plan is missing, deleted, or needs to be re-provisioned without running a full Terraform apply.
---

# Provision Incident Response Plan

You create the `orders-api-health-response` incident response plan resource on the Azure SRE Agent using the ARM REST API.

## When to use

Use this skill when:

- The incident response plan is missing or was accidentally deleted
- Initial provisioning skipped Terraform azapi and the plan was never created
- You are asked to (re)create or verify the incident response plan

## How to provision

### Step 1 — Resolve inputs

Collect the following values before proceeding:

- `AGENT_ID`: the full ARM resource ID of the SRE Agent (`Microsoft.App/agents/{name}`)
- `ALERT_RULE_ID`: the full ARM resource ID of the `alert-orders-api-health` scheduled query rule
- `ACTION_MODE`: either `Review` (default) or `Automatic`

Retrieve them from Terraform outputs if available:

```bash
AGENT_ID="$(terraform -chdir=infra output -raw agent_id)"
ALERT_RULE_ID="$(terraform -chdir=infra output -raw orders_api_health_alert_id)"
ACTION_MODE="$(terraform -chdir=infra output -raw action_mode)"
```

Or resolve `AGENT_ID` and `ALERT_RULE_ID` via `az resource list` if Terraform outputs are unavailable.

### Step 2 — Create the resource

```bash
az rest --method PUT \
  --url "${AGENT_ID}/incidentResponsePlans/orders-api-health-response?api-version=2026-01-01" \
  --body "{
    \"properties\": {
      \"displayName\": \"Orders API Health Check Response\",
      \"trigger\": {
        \"type\": \"AzureMonitorAlert\",
        \"alertRuleId\": \"${ALERT_RULE_ID}\"
      },
      \"routeTo\": {
        \"agentName\": \"orchestrator-agent\"
      },
      \"actionMode\": \"${ACTION_MODE}\"
    }
  }"
```

### Step 3 — Verify

Confirm the resource exists:

```bash
az rest --method GET \
  --url "${AGENT_ID}/incidentResponsePlans/orders-api-health-response?api-version=2026-01-01"
```

A `200` response with `provisioningState: Succeeded` means the plan is active.

## Output format

```md
## Incident Response Plan Provisioning

**Plan name:** orders-api-health-response
**Agent:** {agent name}
**Alert rule:** {alert rule name}
**Action mode:** {Review|Automatic}
**Status:** {Created|Already exists|Failed}

### Result
{az rest response summary or error}

### Next steps
{any follow-up required, or "None — plan is active"}
```

## Safety rules

- This is a PUT (idempotent) — safe to rerun; it will overwrite an existing plan with the same config.
- Do not change `actionMode` to `Automatic` without explicit user approval.
- Confirm the `alertRuleId` resolves to a real resource before creating the plan.
