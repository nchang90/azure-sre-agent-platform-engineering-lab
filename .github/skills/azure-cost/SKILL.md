---
name: azure-cost
description: Estimate Azure pricing and analyze Azure spend using cost breakdowns, forecasts, and optimization recommendations.
---

# Azure Cost Management

Use this skill when users ask for Azure pricing estimates, billing breakdowns, spend forecasting, or cost optimization.

## When to use

- Estimate Azure pricing for a proposed architecture
- Understand current Azure spend by scope or service
- Forecast upcoming cloud costs
- Investigate cost spikes
- Identify optimization opportunities and waste

## Workflow

1. Confirm the scope (subscription, resource group, or management group).
2. Gather the required timeframe and services.
3. Check whether authorized Azure Cost Management data and an applicable budget
   are available; distinguish unavailable data from zero spend.
4. Produce actual cost, forecast, budget consumption, and agent-unit consumption
   only when each value is available from an authorized source.
5. Separate billed cost, forecast, configured limits, and estimates. State
   currency, time range, source, and timestamp.
6. Add optimization recommendations and prioritize safe, high-impact savings
   actions without making changes.

## Guardrails

- Be explicit about assumptions used for estimates.
- Separate actual billed cost from projected cost.
- Do not treat a report threshold as an enforced Azure budget or usage limit.
- Use warning at 80% and critical at 100% only for configured budgets or limits;
  report an absent limit as unconfigured.
- Do not invent spend, forecast, budget, or agent-unit consumption when data is
  missing or access is unavailable.
- Do not claim exact pricing when inputs are incomplete.
- Do not request or expose secrets.
