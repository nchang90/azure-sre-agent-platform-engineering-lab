---
description: |
  Weekly sweep for documentation this repo's code has made wrong. A pre-agent
  step finds the stale documents; the agent writes the corrections into a draft
  pull request.

on:
  schedule:
    - cron: "weekly on monday"
  workflow_dispatch:

if: github.repository_owner == 'nchang90'

# copilot-requests lets the engine use the built-in github.token, so this
# workflow needs no COPILOT_GITHUB_TOKEN secret.
permissions:
  contents: read
  copilot-requests: write

# Backstop only. The real protection is the anti-retry rule in "Write the
# corrections" below: a deterministic create_pull_request failure must not be
# retried, or the run burns its budget looping on the same error.
max-turns: 20

steps:
  - name: Find stale documentation
    run: |
      python3 .github/workflows/docs-drift-check/find_stale_docs.py \
        > "$GITHUB_WORKSPACE/stale-docs.json"
      cat "$GITHUB_WORKSPACE/stale-docs.json"

safe-outputs:
  create-pull-request:
    title-prefix: "[docs] "
    labels: [docs-drift]
    draft: true
    if-no-changes: ignore
    # Both patterns: "**/*.md" does not match a file at the repository root.
    allowed-files: ["**/*.md", "*.md"]
    fallback-as-issue: true
---

# Documentation drift check

The weekly documentation sweep of this Azure SRE Agent lab. A pre-agent step
has already found every document the code has made wrong. Fix what prose can
fix and open a draft pull request.

## Step 1: Read the findings

Read `stale-docs.json` from the workspace. It was computed by
`find_stale_docs.py`, and it — not you — decides what counts as stale.
**Do not go hunting for other problems.** The point of the design is that the
same commit produces the same decision across model versions.

| Field | Meaning |
|---|---|
| `stale_count` | How many documents are wrong. `0` means there is nothing to do |
| `findings[]` | `file` and `problem`, one per correction to make |

If `stale_count` is `0`, stop without opening a pull request.

## Step 2: Write the corrections

Fix every finding. Where each kind belongs in this repo:

| Finding | Where the correction goes |
|---|---|
| A dead relative link | repoint it, or drop it if the target is gone. Many live in `knowledge-base/` runbooks |
| A tfvars key nothing explains | the scenario's own `scenarios/s*/README.md`, and the tfvars guidance in `scenarios/README.md` |

Markdown only. Never edit a script, YAML or Terraform file to make a finding
go away — if prose cannot fix one, leave it alone and list it in the pull
request body under **Needs a code change**.

Match the house style: short sections, tables over prose for anything
enumerable, relative markdown links, and the scenario READMEs' existing
heading structure. Do not restructure a document you are correcting.

For each fix the pull request body gives the document, the `problem` string
that identified it, and the correction, so a reviewer can check the decision
without rerunning anything.

If `create_pull_request` fails deterministically — "No changes to commit", a
rejected path — **do not retry it**. The failure will repeat.
