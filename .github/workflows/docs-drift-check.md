---
description: |
  Checks a merged pull request for documentation the change made wrong. A
  pre-agent step computes the findings; the agent writes the corrections into a
  draft pull request and reports back on the source PR.

on:
  pull_request:
    types: [closed]
    branches: [main]
  workflow_dispatch:
    inputs:
      pr_number:
        description: "Pull request number to analyse"
        required: false
        type: string

if: >-
  (github.event.pull_request.merged == true || github.event_name == 'workflow_dispatch')
  && github.repository_owner == 'nchang90'

permissions:
  contents: read
  pull-requests: read

# Each dispatch gets its own slot; otherwise re-running an older PR cancels the
# conclusion job of the one already in flight.
concurrency:
  job-discriminator: ${{ github.event.pull_request.number || github.event.inputs.pr_number || github.run_id }}

# Backstop only. The real protection is the anti-retry rule in "Write the
# corrections" below: a deterministic create_pull_request failure must not be
# retried, or the run burns its budget looping on the same error.
max-turns: 30

steps:
  - name: Compute drift signals
    env:
      PR_NUMBER: ${{ github.event.pull_request.number || github.event.inputs.pr_number }}
      GH_TOKEN: ${{ github.token }}
    run: |
      CHANGED_FILES="$(gh pr view "$PR_NUMBER" --json files --jq '.files[].path')"
      export CHANGED_FILES
      python3 .github/workflows/docs-drift-check/compute_signals.py \
        > "$GITHUB_WORKSPACE/drift-signals.json"
      cat "$GITHUB_WORKSPACE/drift-signals.json"

safe-outputs:
  create-pull-request:
    title-prefix: "[docs] "
    labels: [docs-drift]
    draft: true
    if-no-changes: ignore
    allowed-files: ["**/*.md"]
    protected-files: blocked
    fallback-as-issue: true
  add-comment:
    max: 1
---

# Documentation drift check

A pull request just merged into this Azure SRE Agent lab. Decide whether it
left any documentation wrong, fix what prose can fix, and report on the source
pull request.

## Step 1: Read the signals

Read `drift-signals.json` from the workspace. It was computed by
`compute_signals.py`, and it — not you — decides what counts as drift.
**Do not re-derive these findings from the diff.** The point of the design is
that the same commit produces the same decision across model versions.

| Field | Meaning |
|---|---|
| `recommendation` | `docs_required` when this PR touched a file with a finding |
| `gating_count` | Findings in files this PR changed — the ones you must act on |
| `advisory_count` | Pre-existing findings elsewhere — not this PR's problem |
| `findings[]` | `file`, `problem`, `fix`, `gating` |

`fix` is already decided for you: `docs` means prose is the fix, `code` means
it is not. Never edit a script, YAML or Terraform file to make a `code`
finding go away.

## Step 2: Decide

- `recommendation == "docs_required"` → continue.
- `recommendation == "docs_optional"` → no pull request. Go to Step 4 and
  report `skipped`. Do not open a PR for advisory findings.

Prefer acting over skipping. A wrong correction costs a closed draft PR; a
missed one leaves the documentation lying to the next reader.

## Step 3: Write the corrections

Fix every gating finding whose `fix` is `docs`. Where each kind belongs in
this repo:

| Finding | Where the correction goes |
|---|---|
| A tfvars key nothing explains | the scenario's own `scenarios/s*/README.md`, and the tfvars guidance in `scenarios/README.md` |
| A dead relative link | repoint it, or drop it if the target is gone. Many live in `knowledge-base/` runbooks |
| A response-plan field that is never sent | the response-plan README in `recipes/.../incident-filters/`, which documents the supported field set |

Match the house style: short sections, tables over prose for anything
enumerable, relative markdown links, and the scenario READMEs' existing
heading structure. Do not restructure a document you are correcting.

For each fix the pull request body gives the doc line, the `problem` string
that identified it, and the correction, so a reviewer can check the decision
without rerunning anything. List `code` findings under **Code changes needed**
with the file and problem, and leave the code alone.

If `create_pull_request` fails deterministically — "No changes to commit", a
rejected path, a protected file — **do not retry it**. The failure will
repeat. Go to Step 4 and report `draft_failed` with the error.

## Step 4: Report on the source pull request

Post exactly one comment, whichever branch you took:

- `drafted` — the docs PR you opened, one line per finding fixed
- `skipped` — no documentation was affected, citing `recommendation`
- `draft_failed` — documentation *was* affected but no PR was produced, with
  the error. Never report this as a clean skip.
