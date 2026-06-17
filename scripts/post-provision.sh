#!/usr/bin/env bash
set -euo pipefail

# ── logging ──
log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }

# ── paths & deps ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
TEMP_DIR="$SCRIPT_DIR/.tmp"
mkdir -p "$TEMP_DIR"
RESP="$TEMP_DIR/resp.json"
trap 'rm -rf "$TEMP_DIR"' EXIT

PYTHON="$(command -v python3 || command -v python)" || { err "Python not found"; exit 1; }
command -v jq >/dev/null                            || { err "jq not found";     exit 1; }

GITHUB_REPO="${GITHUB_REPO:-NickAzureDevops/azure-sre-agent-platform-engineering-lab}"

# ── read values from Terraform state ──
log "Loading Terraform outputs..."
TF_OUT="$(terraform -chdir=infra output -json 2>/dev/null || true)"
[[ -n "$TF_OUT" ]] || { err "Terraform outputs missing — run 'terraform apply' first"; exit 1; }
read_tf() { jq -r ".${1}.value // empty" <<<"$TF_OUT"; }

AGENT_ID="$(read_tf agent_id)"
[[ -n "$AGENT_ID" ]] || { err "agent_id missing from Terraform outputs"; exit 1; }
RESOURCE_GROUP="$(cut -d/ -f5 <<<"$AGENT_ID")"
AGENT_NAME="$(cut -d/ -f9 <<<"$AGENT_ID")"

# The data-plane host has a unique generated suffix — read it from the live resource.
log "Resolving agent data-plane endpoint..."
AGENT_ENDPOINT="$(az resource show --ids "$AGENT_ID" --query properties.agentEndpoint -o tsv 2>/dev/null | tr -d '\r')"
[[ -n "$AGENT_ENDPOINT" ]] || { AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"; warn "Falling back to Terraform output: $AGENT_ENDPOINT"; }
AGENT_ENDPOINT="${AGENT_ENDPOINT%/}"
[[ -n "$AGENT_ENDPOINT" ]] || { err "Could not resolve agent endpoint"; exit 1; }


# Fetches a short-lived Bearer token for the SRE Agent data-plane.
TOKEN=""
auth() {
  TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null)" \
    || { err "Failed to get access token — run 'az login' first"; exit 1; }
}

# Calls the SRE Agent data-plane API.
# Usage: api METHOD /path [extra curl flags...]
# Prints the HTTP status code; response body is written to $RESP.
api() {
  local method="$1" path="$2"; shift 2
  curl -s -o "$RESP" -w "%{http_code}" --connect-timeout 15 --max-time 60 \
    -X "$method" "${AGENT_ENDPOINT}${path}" \
    -H "Authorization: Bearer $TOKEN" \
    "$@" || echo "000"
}

is_ok_status() {
  local code="$1"; shift
  local allowed=(200 201 202 204 "$@")
  local s
  for s in "${allowed[@]}"; do
    [[ "$code" == "$s" ]] && return 0
  done
  return 1
}

# Converts a YAML agent config to JSON and registers it with the agent.
register_subagent() {
  local yaml="$1" name="$2"
  local body="$TEMP_DIR/agent.json"

  "$PYTHON" "$SCRIPT_DIR/yaml-to-api-json.py" "$yaml" >"$body" 2>"$TEMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TEMP_DIR/err")"; return; }

  local code
  code="$(api PUT "/api/v2/extendedAgent/agents/$name" \
    -H "Content-Type: application/json" \
    --data-binary @"$body")"

  is_ok_status "$code" && ok "  Registered: $name" || warn "  $name returned HTTP $code"
}

# ── main ──

echo
echo "============================================="
echo "  SRE Agent Lab — Post-Provision Setup"
echo "============================================="
ok "Agent: $AGENT_ENDPOINT"
ok "RG:    $RESOURCE_GROUP"
ok "Name:  $AGENT_NAME"
echo

auth

# ── Step 1: knowledge base ──
log "Step 1/5: Uploading knowledge base..."
upload=(-F triggerIndexing=true)
names=""
for f in knowledge-base/*.md; do
  upload+=(-F "files=@${f};type=text/plain")
  names+=" $(basename "$f")"
done
code="$(api POST /api/v1/AgentMemory/upload "${upload[@]}")"
is_ok_status "$code" && ok "  Uploaded:$names" || warn "  Knowledge base upload returned HTTP $code"
echo

# ── Step 2: skills ──
log "Step 2/5: Uploading skills..."
for f in .github/skills/*/SKILL.md; do
  [[ -f "$f" ]] || continue
  name="$("$PYTHON" "$SCRIPT_DIR/skill-to-api-json.py" "$f" "$TEMP_DIR/skill.json")"
  code="$(api PUT "/api/v2/extendedAgent/skills/${name}" \
    -H "Content-Type: application/json" \
    --data-binary @"$TEMP_DIR/skill.json")"
  is_ok_status "$code" && ok "  Skill: $name" || warn "  Skill $name returned HTTP $code"
done
echo

# ── Step 3: subagents (specialists registered before orchestrator so handoffs resolve) ──
log "Step 3/5: Registering subagents..."
register_subagent sre-config/agents/triage-agent.yaml         triage-agent
register_subagent sre-config/agents/issue-triager.yaml        issue-triager
register_subagent sre-config/agents/remediation-advisor.yaml  remediation-advisor
register_subagent sre-config/agents/alert-investigator.yaml   alert-investigator
register_subagent sre-config/agents/orchestrator-agent.yaml   incident-orchestrator
echo

# ── Step 4: response plan ──
# Routes all orders-api alerts to the incident-orchestrator agent.
log "Step 4/5: Creating response plan..."
plan='{
  "id":           "orders-api-errors",
  "name":         "Orders API Errors",
  "priorities":   ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "titleContains": "",
  "handlingAgent": "incident-orchestrator",
  "agentMode":    "autonomous",
  "maxAttempts":  3
}'
code="$(api PUT /api/v1/incidentPlayground/filters/orders-api-errors \
  -H "Content-Type: application/json" \
  --data-binary "$plan")"
is_ok_status "$code" 409 && ok "  Response plan → incident-orchestrator" || warn "  Response plan returned HTTP $code"
echo

# ── Step 5: GitHub integration ──
log "Step 5/5: GitHub integration..."
REPO_NAME="$(cut -d/ -f2 <<<"$GITHUB_REPO")"

# Register the GitHub OAuth connector (data-plane).
code="$(api PUT /api/v2/extendedAgent/connectors/github \
  -H "Content-Type: application/json" \
  -d '{"name":"github","type":"AgentConnector","properties":{"dataConnectorType":"GitHubOAuth","dataSource":"github-oauth"}}')"
is_ok_status "$code" && ok "  GitHub OAuth connector created" || warn "  GitHub OAuth connector returned HTTP $code"

# If the agent needs OAuth authorization, surface the URL for the user to open.
api GET /api/v1/github/config >/dev/null 2>&1 || true
OAUTH_URL="$(jq -r '.oAuthUrl // .OAuthUrl // empty' "$RESP" 2>/dev/null || true)"
if [[ -n "$OAUTH_URL" ]]; then
  echo
  echo "  Authorize the SRE Agent to access GitHub:"
  echo "  $OAUTH_URL"
  echo
  if [[ -t 0 ]]; then
    read -r -p "  Open the URL above, authorize, then press Enter to continue..." _
  else
    warn "  Non-interactive shell — open the URL above, authorize, then re-run."
  fi
fi

# Re-auth in case the OAuth flow took long enough for the token to expire.
auth
code="$(api PUT "/api/v2/repos/${REPO_NAME}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${REPO_NAME}\",\"type\":\"CodeRepo\",\"properties\":{\"url\":\"https://github.com/${GITHUB_REPO}\",\"authConnectorName\":\"github\"}}")"
is_ok_status "$code" \
  && ok  "  Code repo: $GITHUB_REPO" \
  || warn "  Code repo returned HTTP $code (authorize GitHub first / check SRE Agent Administrator role)"
echo

echo "============================================="
echo "  Post-provision setup completed"
echo "============================================="
echo "  Agent Portal: https://sre.azure.com"
echo "  Agent API:    $AGENT_ENDPOINT"
echo
echo "  Verify in the portal:"
echo "    Builder → Subagents     (expect 5)"
echo "    Builder → Skills        (expect 6)"
echo "    Incident Response Plans (expect 1)"
echo "    Settings → Incident Platform (Azure Monitor)"
echo "    Code → Repositories     ($GITHUB_REPO)"
echo
