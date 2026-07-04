#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

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
TF_OUT="$(terraform -chdir=infra/terraform output -json 2>/dev/null || true)"
[[ -n "$TF_OUT" ]] || { err "Terraform outputs missing — run 'terraform apply' first"; exit 1; }
read_tf() { jq -r ".${1}.value // empty" <<<"$TF_OUT"; }

TF_AGENT_ID="$(read_tf agent_id)"
AGENT_ID="${AGENT_ID:-$TF_AGENT_ID}"
AGENT_ENDPOINT="${AGENT_ENDPOINT:-}"

[[ -n "$AGENT_ID" ]] || { err "agent_id missing from Terraform outputs and AGENT_ID env var"; exit 1; }
AGENT_SUBSCRIPTION_ID="$(cut -d/ -f3 <<<"$AGENT_ID")"

if [[ -z "$AGENT_ENDPOINT" ]]; then
  log "Resolving agent data-plane endpoint..."
  AGENT_ENDPOINT="$(az resource show --ids "$AGENT_ID" --query properties.agentEndpoint -o tsv 2>/dev/null | tr -d '\r')"
  [[ -n "$AGENT_ENDPOINT" ]] || { AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"; warn "Falling back to Terraform output: $AGENT_ENDPOINT"; }
else
  log "Using AGENT_ENDPOINT override from environment."
fi
AGENT_ENDPOINT="${AGENT_ENDPOINT%/}"
[[ -n "$AGENT_ENDPOINT" ]] || { err "Could not resolve agent endpoint"; exit 1; }

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
    die "Wrong Azure subscription ($current_sub). Run: az account set --subscription $AGENT_SUBSCRIPTION_ID"
  fi
}

to_bool() {
  [[ "$1" == "true" ]] && echo "true" || echo "false"
}

resolve_platform_folder() {
  case "$(printf '%s' "${INCIDENT_PLATFORM:-azure-monitor}" | tr '[:upper:]' '[:lower:]')" in
    servicenow) echo "servicenow" ;;
    azure-monitor|azmonitor|"") echo "azure-monitor" ;;
    *)
      warn "Unknown INCIDENT_PLATFORM='${INCIDENT_PLATFORM:-}'; defaulting to azure-monitor"
      echo "azure-monitor"
      ;;
  esac
}

ENABLE_SEV01_INCIDENT_FILTER="$(to_bool "$(read_tf enable_sev01_incident_filter)")"
ENABLE_DAILY_HEALTH_CHECK="$(to_bool "$(read_tf enable_daily_health_check)")"
PLATFORM_FOLDER="$(resolve_platform_folder)"

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

put_json_file() {
  local path="$1" file="$2"
  api PUT "$path" -H "Content-Type: application/json" --data-binary @"$file"
}

put_json_body() {
  local path="$1" body="$2"
  api PUT "$path" -H "Content-Type: application/json" --data-binary "$body"
}

best_effort_delete() {
  local path="$1"
  api DELETE "$path" >/dev/null 2>&1 || true
}

# GitHub integration step is defined in a separate file for maintainability.
source "$SCRIPT_DIR/github.sh"

# Converts a YAML agent config to JSON and registers it with the agent.
register_subagent() {
  local yaml="$1" name="$2"
  local body="$TEMP_DIR/agent.json"

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml" >"$body" 2>"$TEMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TEMP_DIR/err")"; return; }

  local code
  code="$(put_json_file "/api/v2/extendedAgent/agents/$name" "$body")"

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
    code="$(put_json_file "/api/v2/extendedAgent/skills/${name}" "$TEMP_DIR/skill.json")"
    is_ok_status "$code" && ok "  Skill: $name" || warn "  Skill $name returned HTTP $code"
  done
  echo
}

register_subagents_step() {
  log "Step 3/5: Registering subagents..."

  # Core agents used by the main S1/S3/S4 paths.
  register_subagent recipes/azmon-lawappinsights/agents/triage-agent.yaml         triage-agent
  register_subagent recipes/azmon-lawappinsights/agents/issue-triager.yaml        issue-triager
  register_subagent recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml   incident-orchestrator

  if [[ "$ENABLE_SEV01_INCIDENT_FILTER" == "true" || "$ENABLE_DAILY_HEALTH_CHECK" == "true" ]]; then
    register_subagent recipes/azmon-lawappinsights/agents/alert-investigator.yaml   alert-investigator
  else
    # Keep the portal clean when optional automations are disabled.
    best_effort_delete /api/v2/extendedAgent/agents/alert-investigator
    ok "  Skipped optional subagent: alert-investigator"
  fi
  echo
}

register_response_plan_file() {
  local plan_yaml="$1" code plan_body plan_id handling_agent
  [[ -f "$plan_yaml" ]] || { warn "  Missing response plan YAML: $plan_yaml"; return; }

  plan_body="$("$PYTHON" "$SCRIPT_DIR/build-api.py" incident-filter "$plan_yaml" 2>"$TEMP_DIR/err")" \
    || { warn "  Could not parse response plan YAML ($plan_yaml): $(cat "$TEMP_DIR/err")"; return; }

  plan_id="$(jq -r '.id // empty' <<<"$plan_body")"
  handling_agent="$(jq -r '.handlingAgent // "default"' <<<"$plan_body")"
  [[ -n "$plan_id" ]] || { warn "  Response plan YAML missing id: $plan_yaml"; return; }

  code="$(put_json_body "/api/v1/incidentPlayground/filters/${plan_id}" "$plan_body")"
  is_ok_status "$code" 409 && ok "  Response plan -> ${handling_agent} (${plan_id})" || warn "  ${plan_id} returned HTTP $code"
}

create_response_plans_step() {
  log "Step 4/5: Creating response plan..."
  local code prior_id
  local plan

  for plan in orders-api-health-response orders-api-errors orders-api-latency container-apps-alerts; do
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/${PLATFORM_FOLDER}/incident-filters/${plan}.yaml"
  done

  if [[ "$PLATFORM_FOLDER" == "azure-monitor" ]] && [[ "$ENABLE_SEV01_INCIDENT_FILTER" == "true" ]]; then
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/${PLATFORM_FOLDER}/incident-filters/azmon-sev01.yaml"
  fi

  if [[ "$ENABLE_DAILY_HEALTH_CHECK" == "true" ]]; then
    api GET /api/v1/scheduledtasks >/dev/null 2>&1 || true
    prior_id="$(jq -r 'if type=="array" then .[] else (.value[]?) end | select(.name=="daily-health-check") | .id // empty' "$RESP" 2>/dev/null | head -n1)"
    [[ -n "$prior_id" ]] && api DELETE "/api/v1/scheduledtasks/$prior_id" >/dev/null 2>&1 || true
    code="$(api POST /api/v1/scheduledtasks \
      -H "Content-Type: application/json" \
      --data-binary '{"name":"daily-health-check","description":"Daily 8am health summary across all monitored resources","cronExpression":"0 8 * * *","agentPrompt":"Summarize the last 24h of incidents, fired alerts, and resource health for all monitored resource groups. Flag anything that needs attention.","agent":"alert-investigator"}')"
    is_ok_status "$code" && ok "  Scheduled task -> alert-investigator (daily 08:00)" || warn "  daily-health-check returned HTTP $code"
  fi
  echo
}

ok "Agent: $AGENT_ENDPOINT"

auth
check_subscription_context

upload_knowledge_base
upload_skills
register_subagents_step
create_response_plans_step
setup_github_integration
ok "Post-provision setup completed"
