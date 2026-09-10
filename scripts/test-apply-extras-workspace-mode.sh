#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/apply-extras.sh
source "$SCRIPT_DIR/apply-extras.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

RESP="$test_dir/resp.json"
TMP_DIR="$test_dir/tmp"
mkdir -p "$TMP_DIR"

cat >"$RESP" <<'JSON'
{"error":{"code":"ValidationFailure","message":"The object validation failed: Errors: \nNew agent-to-agent handoffs are not supported in workspace mode. Existing handoffs may only be retained or removed. Deliver cross-agent capabilities through skills and Task-based subagents instead..","details":null}}
JSON

workspace_mode_handoffs_unsupported

body="$test_dir/agent.json"
cat >"$body" <<'JSON'
{"properties":{"instructions":"Original instructions.","handoffs":["incident-summary-agent"]}}
JSON

remove_agent_handoffs_for_workspace_mode "$body"

jq -e '.properties.handoffs == []' "$body" >/dev/null
jq -e '.properties.instructions | contains("Original instructions.") and contains("Workspace mode fallback: agent-to-agent handoffs are unavailable in this environment.")' "$body" >/dev/null

echo "apply-extras workspace-mode fallback test passed"
