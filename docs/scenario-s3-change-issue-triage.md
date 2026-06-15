# S3 - Change Issue Triage

Persona: Support / Automation

## Story

The morning after S2, customer issues flood GitHub. The `issue-triager` runs on schedule, extracts CR numbers, looks them up in `change-lookup`, classifies issues, applies labels, and posts structured triage comments. No human has to read every ticket — the agent handles first-pass triage automatically.

<img src="../images/story3.png" alt="change issue triage" width="600" />

## Azure SRE Agent Concepts

| Concept | What you see in this scenario |
|---------|-------------------------------|
| **Scheduled Tasks** | `issue-triager` runs on a schedule (every 12 hours) — no alert or human message triggers it |
| **GitHub connector (native tools)** | `issue-triager` uses built-in GitHub tools (`FetchGithubIssues`, `CreateGithubIssueComment`, `UpdateGithubIssue`) without any MCP configuration |
| **Knowledge base** | Agent applies `github-issue-triage.md` and `change-management-runbook.md` to classify each issue and recommend next steps |
| **change-lookup integration** | For issues mentioning a CHG number, the agent calls `change-lookup /changes/{cr}` to fetch risk, status, and description |
| **Idempotent triage** | Agent skips issues already triaged (existing bot comment + labels) — safe to run multiple times |
| **Structured output** | Each triage comment follows a fixed schema: Classification, Linked CR, CR Status, Summary, Recommended next steps |

## Scenario Dependencies

- **Requires:** S1 or S2 run first — the sample issues reference `CHG0030001` and the rogue revision from that incident
- **Requires:** GitHub connector configured (OAuth sign-in or fine-grained PAT with `Issues:Read+Write`)
- **Unlocks:** S4 - enterprise controls scenario can reuse issue classifications for ServiceNow and GitHub handoff consistency checks

## Run

```bash
bash scripts/create-sample-issues.sh OWNER/REPO
```

Sample issues created:

- `[Customer Issue] orders-api 500s spiked after CHG0030001 last night`
- `[Customer Issue] Checkout intermittently failing, possibly related to CHG0030002`
- `[Customer Issue] Deploy without a linked CR got through, paved road issue`
- `[Customer Issue] Who owns change-management-runbook.md?`

## Step by Step

1. `create-sample-issues.sh` opens four customer issues in the connected GitHub repo.
2. The `issue-triager` scheduled task fires (or you can trigger it manually from the agent portal).
3. For each open `[Customer Issue]` issue without a bot comment, `issue-triager` fetches the body and existing labels.
4. It extracts any CHG number from the title or body.
5. If a CHG number is found, it calls `change-lookup /changes/{cr}` and retrieves risk tier and status.
6. It classifies the issue using `github-issue-triage.md` rules.
7. It applies the appropriate label set (e.g. `change-related`, `chg0030001`, `high`).
8. It posts a structured triage comment following the `🤖 **SRE Agent**` template.
9. On subsequent runs, already-triaged issues are skipped.

## Portal Steps

1. Open [sre.azure.com](https://sre.azure.com) → your agent → **Scheduled Tasks**.
2. Find the `issue-triager` task and click **Run now** to trigger it immediately.
3. Watch the task thread — you will see one `FetchGithubIssues` call followed by individual issue processing.
4. Open your GitHub repo's Issues tab and verify each `[Customer Issue]` now has a bot comment and labels.

## Suggested Prompts

Start a new chat thread with the agent to inspect what it learned:

- *"Summarize all customer issues triaged this morning"*
- *"Which issues were linked to CHG0030001 and what was their classification?"*
- *"Are there any policy-violation issues open right now?"*
- *"What labels did you apply to the 'Deploy without a linked CR' issue and why?"*

## Expected Output

Within one schedule cycle, each customer issue has a bot triage comment with:
- Classification (e.g. `Change-Related-Incident`, `Policy-Violation`, `Question`)
- Linked CR number and risk context (from `change-lookup`)
- Recommended next steps based on the triage runbook
- Labels applied (e.g. `change-related`, `chg0030001`, `high`, `policy-violation`)

## Validation

```bash
gh issue list -R OWNER/REPO --search '"[Customer Issue]"' --json number,labels
gh issue view <number> -R OWNER/REPO --comments | grep -i 'SRE Agent'
```

## Knowledge Base

- [github-issue-triage.md](../knowledge-base/github-issue-triage.md)
- [change-management-runbook.md](../knowledge-base/change-management-runbook.md)
