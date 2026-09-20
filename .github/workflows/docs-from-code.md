---
description: |
  Documentation the code has outrun. When a code change lands on main, a
  pre-agent step resolves which documents own the changed paths; the agent
  writes the updates into a draft pull request.

on:
  push:
    branches: [main]
    # The roots of the OWNERS table in resolve_doc_targets.py, minus markdown.
    # Without this the workflow re-fires on the documentation pull requests it
    # opens itself, and burns an agent run to conclude there is nothing to do.
    paths:
      - "src/**"
      - "infra/**"
      - "scripts/**"
      - "recipes/**"
      - "scenarios/**"
      - "!**/*.md"
  workflow_dispatch:

if: github.repository_owner == 'nchang90'

# copilot-requests lets the engine use the built-in github.token, so this
# workflow needs no COPILOT_GITHUB_TOKEN secret.
permissions:
  contents: read
  copilot-requests: write

# Sized against a known failure, not guessed. Every docs-drift-check run so far
# has died on "Maximum LLM invocations exceeded (20 / 20)" without opening a
# pull request, because the agent spent its whole budget grepping for context.
# The real fix is that "Step 1" below hands the agent that context instead; this
# is the backstop.
max-turns: 30

steps:
  - name: Resolve documentation targets
    run: |
      # The pre-agent step compares the pushed commit against its first parent,
      # so a shallow checkout has to be deepened by one before it can diff.
      git fetch --no-tags --deepen=1 origin "$GITHUB_SHA" 2>/dev/null || true
      python3 .github/workflows/docs-from-code/resolve_doc_targets.py \
        > "$GITHUB_WORKSPACE/doc-targets.json"
      cat "$GITHUB_WORKSPACE/doc-targets.json"

safe-outputs:
  create-pull-request:
    title-prefix: "[docs] "
    labels: [docs-from-code]
    draft: true
    if-no-changes: ignore
    # Both patterns: "**/*.md" does not match a file at the repository root.
    allowed-files: ["**/*.md", "*.md"]
    fallback-as-issue: true
---

# Documentation from code

A code change just landed on main. A pre-agent step has already resolved which
documents own the paths it touched. Update those documents and open a draft
pull request.

This workflow is the counterpart to [the weekly drift check](./docs-drift-check.md):
that one finds documents the code made *wrong*, this one finds documents the
code made *incomplete*. Neither hunts for the other's findings.

## Step 1: Read the resolved targets

Read `doc-targets.json` from the workspace. It was computed by
`resolve_doc_targets.py`, and its `OWNERS` table — not you — decides which
document a code path belongs in. **Do not go looking for other documents to
change, and do not grep the repository for context this file already gives
you.** Exploring is what exhausts the turn budget before the pull request
gets opened.

| Field | Meaning |
|---|---|
| `base_resolved` | `false` means the diff never ran. Stop and report it; do not treat it as "nothing to do" |
| `target_count` | How many documents owe an update. `0` means there is nothing to do |
| `targets[]` | `doc` to edit, and the `triggered_by` changes that oblige it |
| `added_identifiers[]` | New terraform variables and tfvars keys, each with `documented` already answered |
| `removed_identifiers[]` | Deleted ones, with `still_documented_in` listing documents that still describe them |

If `target_count` is `0`, stop without opening a pull request.

## Step 2: Write the updates

Work through `targets` in order. Read only the documents named there.

| Signal | What the document owes |
|---|---|
| A `triggered_by` path that is `A`dded | describe the new file where that document lists its siblings |
| A `triggered_by` path that is `D`eleted | remove it, and repoint anything that referenced it |
| An added identifier with `"documented": false` | explain it where the document covers its neighbours |
| A removed identifier with a non-empty `still_documented_in` | delete the description from each document listed |

If `target_count` is more than five, update the first five and list the rest in
the pull request body under **Not covered by this run**. A partial pull request
that opens beats a complete one that runs out of turns.

Markdown only. Never edit a script, YAML or Terraform file to make a target go
away — if prose cannot cover one, leave it and list it under **Needs a code
change**.

Match the house style: short sections, tables over prose for anything
enumerable, relative markdown links, and each document's existing heading
structure. Do not restructure a document you are updating.

For each update the pull request body gives the document, the `triggered_by`
entry or identifier that obliged it, and what you wrote, so a reviewer can
check the routing without rerunning anything.

If `create_pull_request` fails deterministically — "No changes to commit", a
rejected path — **do not retry it**. The failure will repeat.
