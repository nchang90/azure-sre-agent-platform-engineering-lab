# Change Risk Assessment

Use this guide to assess the risk of a proposed Change Request **before** it
enters its implementation window. The SRE Agent runs this assessment when asked
*"What's the risk of CR XYZ?"* in the developer scenario.

## Inputs the agent should gather

| Input | Source |
|-------|--------|
| CR metadata | `change-lookup /changes/{cr}` |
| Linked PR / commit diff | GitHub MCP (`linkedPullRequest` / `linkedCommit`) |
| Files changed | GitHub MCP — repo file tree + commit diff |
| Recent incidents on the same component | App Insights / Log Analytics |
| Test coverage on changed paths | GitHub MCP — search for matching test files |

## Risk-scoring rubric

Score each dimension **0–3**, then sum. Anything **≥ 7** is High risk and should
be treated as `Major` change requiring CAB review.

| Dimension | 0 (low) | 1 | 2 | 3 (high) |
|-----------|---------|---|---|----------|
| **Blast radius** | One internal service | One product surface | One customer-facing API | Multi-region / payments / auth |
| **Lines changed** | < 50 | 50–200 | 200–800 | > 800 |
| **Files in critical paths** | None | 1 config / docs | 1 production code | Many production code |
| **Test coverage delta** | Tests added | Unchanged | Reduced | No tests touched |
| **Time since last incident on this component** | > 90 days | 30–90 d | 7–30 d | < 7 d |
| **Deploy window** | Off-hours, low traffic | Off-hours, normal traffic | Business hours, low | Peak business hours |
| **Rollback verified?** | Tested in staging | Documented + plausible | Plan exists, untested | No plan |

## Output template

The agent should respond with a short, structured assessment:

```text
CR: CHG0030001 — Deploy orders-api v2.4 — pricing tier rollout

Risk score: 8 / 21  → MODERATE

Top risk factors:
1. Touches pricing logic in src/orders-api/Program.cs (production code)
2. No new tests in PR #142 covering the pricing branch
3. Window starts at 14:00 (peak traffic)

Mitigations:
- Stage in dev environment for 30 min before flipping production
- Pre-warm rollback revision: `az containerapp revision activate ...`
- Owner online during the full window: alex.morgan@example.com

Recommendation: Proceed with reduced batch size (10% canary first) and
monitor 5xx rate for 15 min before promoting to 100%.
```

## Hard-block conditions

If **any** of these are true, recommend the CR be deferred:

- No rollback plan documented
- PR has unresolved CI failures
- An incident on the same service closed less than 24 hours ago
- The deploy window overlaps a higher-priority CR
