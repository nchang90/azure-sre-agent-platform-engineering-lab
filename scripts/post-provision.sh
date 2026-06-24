#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

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
ENABLE_GITHUB_INTEGRATION="${ENABLE_GITHUB_INTEGRATION:-false}"
STRICT_GITHUB_OAUTH_CHECK="${STRICT_GITHUB_OAUTH_CHECK:-false}"
GITHUB_PAT="${GITHUB_PAT:-}"
GITHUB_OAUTH_WAIT_SECONDS="${GITHUB_OAUTH_WAIT_SECONDS:-240}"

# ── read values from Terraform state ──
log "Loading Terraform outputs..."
TF_OUT="$(terraform -chdir=infra output -json 2>/dev/null || true)"
[[ -n "$TF_OUT" ]] || { err "Terraform outputs missing — run 'terraform apply' first"; exit 1; }
read_tf() { jq -r ".${1}.value // empty" <<<"$TF_OUT"; }

AGENT_ID="$(read_tf agent_id)"
[[ -n "$AGENT_ID" ]] || { err "agent_id missing from Terraform outputs"; exit 1; }
AGENT_SUBSCRIPTION_ID="$(cut -d/ -f3 <<<"$AGENT_ID")"
RESOURCE_GROUP="$(cut -d/ -f5 <<<"$AGENT_ID")"
AGENT_NAME="$(cut -d/ -f9 <<<"$AGENT_ID")"
AGENT_PORTAL_URL="$(read_tf agent_portal_url)"

# The data-plane host has a unique generated suffix — read it from the live resource.
log "Resolving agent data-plane endpoint..."
AGENT_ENDPOINT="$(az resource show --ids "$AGENT_ID" --query properties.agentEndpoint -o tsv 2>/dev/null | tr -d '\r')"
[[ -n "$AGENT_ENDPOINT" ]] || { AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"; warn "Falling back to Terraform output: $AGENT_ENDPOINT"; }
AGENT_ENDPOINT="${AGENT_ENDPOINT%/}"
[[ -n "$AGENT_ENDPOINT" ]] || { err "Could not resolve agent endpoint"; exit 1; }

# Optional user-assigned identity for connector setup.
AGENT_UAMI="$(az resource show --ids "$AGENT_ID" --query "keys(identity.userAssignedIdentities)[0]" -o tsv 2>/dev/null || true)"


# Fetches a short-lived Bearer token for the SRE Agent data-plane.
TOKEN=""
auth() {
  TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null)" \
    || { err "Failed to get access token — run 'az login' first"; exit 1; }
}

check_subscription_context() {
  local current_sub
  current_sub="$(az account show --query id -o tsv 2>/dev/null || true)"
  if [[ -z "$current_sub" ]]; then
    die "Could not read current Azure subscription context. Run 'az login' first."
  fi
  if [[ "$current_sub" != "$AGENT_SUBSCRIPTION_ID" ]]; then
    err "Active Azure subscription does not match Terraform agent subscription."
    echo "  Active: $current_sub"
    echo "  Agent:  $AGENT_SUBSCRIPTION_ID"
    echo "  Fix:    az account set --subscription $AGENT_SUBSCRIPTION_ID"
    die "Switch subscription and re-run post-provision."
  fi
}

# Calls the SRE Agent data-plane API.
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

require_json_body() {
  local op="$1" code="$2"
  if ! is_ok_status "$code"; then
    die "$op failed with HTTP $code"
  fi
  if ! jq -e . "$RESP" >/dev/null 2>&1; then
    local preview
    preview="$(head -c 140 "$RESP" | tr '\n' ' ')"
    die "$op returned non-JSON response (endpoint mismatch or auth issue). Preview: ${preview}"
  fi
}

api_json() {
  local op="$1" method="$2" path="$3" body="$4"
  local code
  code="$(api "$method" "$path" -H "Content-Type: application/json" --data-binary "$body")"
  require_json_body "$op" "$code"
}

best_effort_delete() {
  local path="$1"
  api DELETE "$path" >/dev/null 2>&1 || true
}

# GitHub integration step is defined in a separate file for maintainability.
source "$SCRIPT_DIR/github.sh"
source "$SCRIPT_DIR/servicenow.sh"

# Converts a YAML agent config to JSON and registers it with the agent.
register_subagent() {
  local yaml="$1" name="$2"
  local body="$TEMP_DIR/agent.json"

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml" >"$body" 2>"$TEMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TEMP_DIR/err")"; return; }

  local code
  code="$(api PUT "/api/v2/extendedAgent/agents/$name" \
    -H "Content-Type: application/json" \
    --data-binary @"$body")"

  is_ok_status "$code" && ok "  Registered: $name" || warn "  $name returned HTTP $code"
}

upload_knowledge_base() {
  log "Step 1/5: Uploading knowledge base..."
  local upload names f code
  upload=(-F triggerIndexing=true)
  names=""
  for f in knowledge-base/*.md; do
    upload+=(-F "files=@${f};type=text/plain")
    names+=" $(basename "$f")"
  done
  code="$(api POST /api/v1/AgentMemory/upload "${upload[@]}")"
  is_ok_status "$code" && ok "  Uploaded:$names" || warn "  Knowledge base upload returned HTTP $code"
  echo
}

upload_skills() {
  log "Step 2/5: Uploading skills..."
  local f name code
  for f in .github/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" skill "$f" "$TEMP_DIR/skill.json")"
    code="$(api PUT "/api/v2/extendedAgent/skills/${name}" \
      -H "Content-Type: application/json" \
      --data-binary @"$TEMP_DIR/skill.json")"
    is_ok_status "$code" && ok "  Skill: $name" || warn "  Skill $name returned HTTP $code"
  done
  echo
}

register_subagents_step() {
  log "Step 3/5: Registering subagents..."
  register_subagent recipes/azmon-lawappinsights/agents/triage-agent.yaml         triage-agent
  register_subagent recipes/azmon-lawappinsights/agents/issue-triager.yaml        issue-triager
  register_subagent recipes/azmon-lawappinsights/agents/remediation-advisor.yaml  remediation-advisor
  register_subagent recipes/azmon-lawappinsights/agents/alert-investigator.yaml   alert-investigator
  register_subagent recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml   incident-orchestrator
  echo
}

create_response_plans_step() {
  log "Step 4/5: Creating response plan..."
  local plan code prior_id

  plan='{
  "id":           "orders-api-health-response",
  "name":         "Orders API Health Response",
  "priorities":   ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "titleContains": "alert-orders-api-health",
  "handlingAgent": "incident-orchestrator",
  "agentMode":    "autonomous",
  "maxAttempts":  3
}'
  code="$(api POST /api/v1/incidentPlayground/filters/orders-api-health-response \
    -H "Content-Type: application/json" \
    --data-binary "$plan")"
  is_ok_status "$code" 409 && ok "  Response plan -> incident-orchestrator (health)" || warn "  Health response plan returned HTTP $code"

  plan='{
  "id":           "orders-api-errors",
  "name":         "Orders API 5xx Errors",
  "priorities":   ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "titleContains": "alert-orders-api-errors",
  "handlingAgent": "incident-orchestrator",
  "agentMode":    "autonomous",
  "maxAttempts":  3
}'
  code="$(api POST /api/v1/incidentPlayground/filters/orders-api-errors \
    -H "Content-Type: application/json" \
    --data-binary "$plan")"
  is_ok_status "$code" 409 && ok "  Response plan -> incident-orchestrator (5xx)" || warn "  5xx response plan returned HTTP $code"

  plan='{
  "id":           "orders-api-latency",
  "name":         "Orders API Latency (P99)",
  "priorities":   ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "titleContains": "alert-orders-api-latency",
  "handlingAgent": "incident-orchestrator",
  "agentMode":    "autonomous",
  "maxAttempts":  3
}'
  code="$(api POST /api/v1/incidentPlayground/filters/orders-api-latency \
    -H "Content-Type: application/json" \
    --data-binary "$plan")"
  is_ok_status "$code" 409 && ok "  Response plan -> incident-orchestrator (latency)" || warn "  Latency response plan returned HTTP $code"

  if [[ "$(read_tf enable_sev01_incident_filter)" == "true" ]]; then
    code="$(api POST /api/v1/incidentPlayground/filters/azmon-sev01 \
      -H "Content-Type: application/json" \
      --data-binary '{"id":"azmon-sev01","name":"Azure Monitor Sev0/Sev1","priorities":["Sev0","Sev1"],"titleContains":"","handlingAgent":"alert-investigator","agentMode":"autonomous","maxAttempts":3}')"
    is_ok_status "$code" 409 && ok "  Response plan -> alert-investigator (Sev0/Sev1)" || warn "  azmon-sev01 returned HTTP $code"
  fi

  if [[ "$(read_tf enable_daily_health_check)" == "true" ]]; then
    api GET /api/v1/scheduledtasks >/dev/null 2>&1 || true
    prior_id="$("$PYTHON" -c "import json,sys
try:
    for t in json.load(open('$RESP')):
        if t.get('name')=='daily-health-check':
            print(t.get('id','')); break
except Exception:
    pass" 2>/dev/null)"
    [[ -n "$prior_id" ]] && api DELETE "/api/v1/scheduledtasks/$prior_id" >/dev/null 2>&1 || true
    code="$(api POST /api/v1/scheduledtasks \
      -H "Content-Type: application/json" \
      --data-binary '{"name":"daily-health-check","description":"Daily 8am health summary across all monitored resources","cronExpression":"0 8 * * *","agentPrompt":"Summarize the last 24h of incidents, fired alerts, and resource health for all monitored resource groups. Flag anything that needs attention.","agent":"alert-investigator"}')"
    is_ok_status "$code" && ok "  Scheduled task -> alert-investigator (daily 08:00)" || warn "  daily-health-check returned HTTP $code"
  fi
  echo
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
check_subscription_context

upload_knowledge_base
upload_skills
register_subagents_step
create_response_plans_step
setup_servicenow_integration
setup_github_integration
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
echo "    Incident Response Plans (expect 1, or 2 with azmon-sev01)"
echo "    Scheduled Tasks         (daily-health-check, if enabled)"
echo "    Settings → Incident Platform (Azure Monitor)"
echo "    Settings → Incident Platform (ServiceNow, if SERVICENOW_* env vars are set)"
if [[ "$ENABLE_GITHUB_INTEGRATION" == "true" ]]; then
  echo "    Code → Repositories     ($GITHUB_REPO)"
fi
echo
