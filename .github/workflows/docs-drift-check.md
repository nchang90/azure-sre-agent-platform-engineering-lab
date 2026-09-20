---
description: |
  Checks a merged pull request for documentation the change made wrong. A
  pre-agent step computes the drift signals; the agent writes the corrections
  into a draft pull request and reports the outcome back on the source PR.

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

A pull request just merged. Decide whether it left any documentation wrong,
fix what you can in markdown, and report the outcome on the source pull request.

## Step 1: Read the signals

Read `drift-signals.json` from the workspace. It was computed by
`compute_signals.py`, and it — not you — decides what counts as drift.
**Do not re-derive these findings from the diff.** The point of the design is
that the same commit produces the same decision across model versions.

| Field | Meaning |
|---|---|
| `recommendation` | `docs_required` when this PR touched a file with a finding, `docs_optional` otherwise |
| `gating_count` | Findings in files this PR changed — the ones you must act on |
| `advisory_count` | Pre-existing findings elsewhere in the repo |
| `findings[]` | `file`, `problem`, and `gating` for each |

Each `problem` is one of:

| Problem | What it means | Fix in markdown? |
|---|---|---|
| `spec.X is never sent` | `build-api.py` emits a fixed key set and the API rejects the rest, so the field does nothing | Only the docs that call it supported — the YAML is a code fix |
| `metadata.name is X but the file is Y` | Plans register by `metadata.name` and are cleaned up by file name, so the plan deletes itself or leaks | No — code fix, report it |
| `selects response plan X but no YAML` | `apply-extras.sh` exits on the missing file | No — code fix, report it |
| `link to X does not exist` | A relative link points at a file that is gone or moved | Yes |
| `reads tfvars key X but no doc mentions it` | A key the scripts require that nothing explains how to set | Yes — document it where that scenario's setup is described |

## Step 2: Decide

- `recommendation == "docs_required"` → continue to Step 3.
- `recommendation == "docs_optional"` → make no pull request. Go to Step 4 and
  report `skipped`. Advisory findings are pre-existing backlog and are **not**
  this pull request's problem; do not open a PR for them.

Prefer acting over skipping. A wrong correction costs a closed draft PR; a
missed one leaves the documentation lying to the next reader.

## Step 3: Write the corrections

Fix every gating finding that can be fixed in a `.md` file. For each one, the
pull request body must give the doc line, the `problem` string that identified
it, and the correction — so a reviewer can check the decision without rerunning
anything.

Findings whose fix is code, not prose, go in the body under **Code changes
needed**, naming the file and the problem. Never edit a script, YAML or
Terraform file to match the docs.

If `create_pull_request` fails deterministically — "No changes to commit", a
rejected path, a protected file — **do not retry it**. The failure will repeat.
Go to Step 4 and report `draft_failed` with the error.

## Step 4: Report on the source pull request

Post exactly one comment on the merged pull request, whichever branch you took:

- `drafted` — the docs PR you opened, and one line per finding fixed
- `skipped` — that no documentation was affected, citing `recommendation`
- `draft_failed` — documentation *was* affected but no PR was produced, with
  the error. Never report this as a clean skip.
