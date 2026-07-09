#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

TMP_DIR="$SCRIPT_DIR/.tmp"
mkdir -p "$TMP_DIR"
RESP="$TMP_DIR/resp.json"
trap 'rm -rf "$TMP_DIR"' EXIT

PYTHON="${PYTHON:-python3}"

AGENT_ID=""
AGENT_ENDPOINT=""
ENABLE_SEV01_INCIDENT_FILTER="false"
ENABLE_DAILY_HEALTH_CHECK="false"
PLATFORM_FOLDER="azure-monitor"
TOKEN=""

CORE_SUBAGENTS=(
  "recipes/azmon-lawappinsights/agents/triage-agent.yaml:triage-agent"
  "recipes/azmon-lawappinsights/agents/issue-triager.yaml:issue-triager"
  "recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml:incident-orchestrator"
)

RESPONSE_PLANS=(
  orders-api-health-response
  orders-api-errors
  orders-api-latency
  container-apps-alerts
)

require_tools() {
  command -v jq >/dev/null || die "jq not found"
  command -v "$PYTHON" >/dev/null || die "Python not found: $PYTHON"
}

normalize_bool() {
  [[ "${1,,}" == "true" ]] && echo "true" || echo "false"
}

resolve_platform_folder() {
  case "$(printf '%s' "${INCIDENT_PLATFORM:-azure-monitor}" | tr '[:upper:]' '[:lower:]')" in
    servicenow) echo "servicenow" ;;
    azure-monitor|azmonitor|"") echo "azure-monitor" ;;
    *)
      warn "Unknown INCIDENT_PLATFORM='${INCIDENT_PLATFORM:-}', defaulting to azure-monitor"
      echo "azure-monitor"
      ;;
  esac
}

load_context_from_terraform() {
  log "Loading Terraform outputs..."
  local tf_out
  tf_out="$(terraform -chdir=infra/terraform output -json 2>/dev/null || true)"
  [[ -n "$tf_out" ]] || die "Terraform outputs missing — run 'terraform apply' first"

  read_tf() { jq -r ".${1}.value // empty" <<<"$tf_out"; }

  AGENT_ID="${AGENT_ID:-$(read_tf agent_id)}"
  AGENT_ENDPOINT="${AGENT_ENDPOINT:-$(read_tf agent_data_plane_url)}"
  ENABLE_SEV01_INCIDENT_FILTER="${ENABLE_SEV01_INCIDENT_FILTER:-$(read_tf enable_sev01_incident_filter)}"
  ENABLE_DAILY_HEALTH_CHECK="${ENABLE_DAILY_HEALTH_CHECK:-$(read_tf enable_daily_health_check)}"

  [[ -n "$AGENT_ID" ]] || die "agent_id missing from Terraform outputs"
}

resolve_agent_endpoint() {
  if [[ -z "$AGENT_ENDPOINT" ]]; then
    AGENT_ENDPOINT="$(az resource show --ids "$AGENT_ID" --query properties.agentEndpoint -o tsv 2>/dev/null | tr -d '\r')"
  fi
  AGENT_ENDPOINT="${AGENT_ENDPOINT%/}"
  [[ -n "$AGENT_ENDPOINT" ]] || die "Could not resolve agent endpoint"
}

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

auth() {
  TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null)" \
    || die "Failed to get access token — run 'az login' first"
}

put_json_file() {
  local path="$1" file="$2"
  api PUT "$path" -H "Content-Type: application/json" --data-binary @"$file"
}

put_json_body() {
  local path="$1" body="$2"
  api PUT "$path" -H "Content-Type: application/json" --data-binary "$body"
}

register_subagent() {
  local yaml_path="$1" name="$2"
  local body="$TMP_DIR/agent.json"

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml_path" >"$body" 2>"$TMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TMP_DIR/err")"; return; }

  local code
  code="$(put_json_file "/api/v2/extendedAgent/agents/$name" "$body")"
  if is_ok_status "$code"; then
    ok "  Registered: $name"
  else
    warn "  $name returned HTTP $code"
  fi
}

register_response_plan_file() {
  local yaml_path="$1"
  local code plan_body plan_id handling_agent

  [[ -f "$yaml_path" ]] || { warn "  Missing response plan YAML: $yaml_path"; return; }

  plan_body="$("$PYTHON" "$SCRIPT_DIR/build-api.py" incident-filter "$yaml_path" 2>"$TMP_DIR/err")" \
    || { warn "  Could not parse response plan YAML ($yaml_path): $(cat "$TMP_DIR/err")"; return; }

  plan_id="$(jq -r '.id // empty' <<<"$plan_body")"
  handling_agent="$(jq -r '.handlingAgent // "default"' <<<"$plan_body")"
  [[ -n "$plan_id" ]] || { warn "  Response plan YAML missing id: $yaml_path"; return; }

  code="$(put_json_body "/api/v1/incidentPlayground/filters/${plan_id}" "$plan_body")"
  if is_ok_status "$code" 409; then
    ok "  Response plan -> ${handling_agent} (${plan_id})"
  else
    warn "  ${plan_id} returned HTTP $code"
  fi
}

upload_knowledge_base() {
  log "Step 1/4: Uploading knowledge base..."
  local upload names f code
  upload=(-F triggerIndexing=true)
  names=""

  for f in knowledge-base/*.md; do
    upload+=(-F "files=@${f};type=text/plain")
    names+=" $(basename "$f")"
  done

  code="$(api POST /api/v1/AgentMemory/upload "${upload[@]}")"
  if is_ok_status "$code"; then
    ok "  Uploaded:$names"
  else
    warn "  Knowledge base upload returned HTTP $code"
  fi
  echo
}

upload_skills() {
  log "Step 2/4: Uploading skills..."
  local f name code

  for f in .github/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" skill "$f" "$TMP_DIR/skill.json")"
    code="$(put_json_file "/api/v2/extendedAgent/skills/${name}" "$TMP_DIR/skill.json")"
    if is_ok_status "$code"; then
      ok "  Skill: $name"
    else
      warn "  Skill $name returned HTTP $code"
    fi
  done
  echo
}

register_subagents() {
  log "Step 3/4: Registering subagents..."
  local item yaml_path name

  for item in "${CORE_SUBAGENTS[@]}"; do
    yaml_path="${item%%:*}"
    name="${item##*:}"
    register_subagent "$yaml_path" "$name"
  done

  if [[ "$ENABLE_SEV01_INCIDENT_FILTER" == "true" || "$ENABLE_DAILY_HEALTH_CHECK" == "true" ]]; then
    register_subagent recipes/azmon-lawappinsights/agents/alert-investigator.yaml alert-investigator
  else
    api DELETE /api/v2/extendedAgent/agents/alert-investigator >/dev/null 2>&1 || true
    ok "  Skipped optional subagent: alert-investigator"
  fi
  echo
}

create_response_plans() {
  log "Step 4/4: Creating response plans..."
  local plan

  for plan in "${RESPONSE_PLANS[@]}"; do
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/${PLATFORM_FOLDER}/incident-filters/${plan}.yaml"
  done
  echo
}

main() {
  require_tools
  load_context_from_terraform
  resolve_agent_endpoint

  PLATFORM_FOLDER="$(resolve_platform_folder)"
  ENABLE_SEV01_INCIDENT_FILTER="$(normalize_bool "$ENABLE_SEV01_INCIDENT_FILTER")"
  ENABLE_DAILY_HEALTH_CHECK="$(normalize_bool "$ENABLE_DAILY_HEALTH_CHECK")"

  ok "Agent: $AGENT_ENDPOINT"
  auth
  upload_knowledge_base
  upload_skills
  register_subagents
  create_response_plans
  ok "Core post-provision setup completed"
}

main "$@"
