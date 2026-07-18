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

ENVIRONMENT=""
AGENT_ID=""
AGENT_ENDPOINT=""
TOKEN=""

SUBAGENTS=(
  "recipes/azmon-lawappinsights/agents/triage-agent.yaml:triage-agent"
  "recipes/azmon-lawappinsights/agents/issue-triager.yaml:issue-triager"
  "recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml:incident-orchestrator"
  "recipes/azmon-lawappinsights/agents/alert-investigator.yaml:alert-investigator"
  "recipes/azmon-lawappinsights/agents/aks-remediator.yaml:aks-remediator"
)

RESPONSE_PLANS=(
  orders-api-health-response
  orders-api-errors
  orders-api-latency
  container-apps-alerts
  azmon-sev01
  aks-critical-errors
)

usage() {
  cat <<'EOF'
Usage: bash scripts/apply-extras.sh [ENVIRONMENT]

ENVIRONMENT selects matching Terraform files:
  infra/terraform/backend/ENVIRONMENT.backend.tfvars
  infra/terraform/environments/ENVIRONMENT.tfvars

Examples:
  bash scripts/apply-extras.sh sbox
  bash scripts/apply-extras.sh demo
EOF
}

parse_args() {
  [[ $# -le 1 ]] || die "Usage: bash scripts/apply-extras.sh [ENVIRONMENT]"
  case "${1:-}" in
    "") ;;
    -h|--help) usage; exit 0 ;;
    -*) die "Unknown option: $1" ;;
    *) ENVIRONMENT="$1" ;;
  esac
}

require_tools() {
  command -v jq >/dev/null || die "jq not found"
  command -v "$PYTHON" >/dev/null || die "Python not found: $PYTHON"
}

configure_environment() {
  [[ -n "$ENVIRONMENT" ]] || return 0

  local backend_file="backend/${ENVIRONMENT}.backend.tfvars"

  [[ -f "infra/terraform/${backend_file}" ]] || die "Missing Terraform backend config: infra/terraform/${backend_file}"
  [[ -f "infra/terraform/environments/${ENVIRONMENT}.tfvars" ]] || die "Missing Terraform environment tfvars: infra/terraform/environments/${ENVIRONMENT}.tfvars"

  log "Selecting Terraform environment: $ENVIRONMENT"
  terraform -chdir=infra/terraform init -reconfigure -backend-config="$backend_file" >/dev/null
}

load_context_from_terraform() {
  log "Loading Terraform outputs..."
  local tf_out tf_err endpoint
  tf_err="$TMP_DIR/terraform-output.err"
  tf_out="$(terraform -chdir=infra/terraform output -json 2>"$tf_err" || true)"
  [[ -n "$tf_out" ]] || die "Terraform outputs missing. Run terraform apply for this environment first. Details: $(tr '\n' ' ' <"$tf_err")"

  AGENT_ID="$(jq -r '.agent_id.value // empty' <<<"$tf_out")"
  [[ -n "$AGENT_ID" ]] || die "agent_id missing from Terraform outputs"

  endpoint="$(az resource show --ids "$AGENT_ID" --query properties.agentEndpoint -o tsv 2>/dev/null | tr -d '\r')"
  AGENT_ENDPOINT="${endpoint%/}"
  [[ -n "$AGENT_ENDPOINT" ]] || die "Could not resolve agent endpoint"
}

api() {
  local method="$1" path="$2"; shift 2
  curl -s -o "$RESP" -w "%{http_code}" --connect-timeout 15 --max-time 60 \
    -X "$method" "${AGENT_ENDPOINT}${path}" \
    -H "Authorization: Bearer $TOKEN" \
    "$@" || echo "000"
}

response_summary() {
  if [[ -s "$RESP" ]]; then
    tr '\n' ' ' <"$RESP" | cut -c1-500
  else
    echo "empty response body"
  fi
}

report_result() {
  local code="$1" success="$2" failure="$3"
  case "$code" in
    200|201|202|204|409) ok "  $success" ;;
    *) warn "  $failure returned HTTP $code: $(response_summary)" ;;
  esac
}

auth() {
  TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null)" \
    || die "Failed to get access token — run 'az login' first"
}

put_json_file() {
  local path="$1" file="$2"
  api PUT "$path" -H "Content-Type: application/json" --data-binary @"$file"
}

register_subagent() {
  local yaml_path="$1" name="$2"
  local body="$TMP_DIR/agent.json" code

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml_path" >"$body" 2>"$TMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TMP_DIR/err")"; return; }

  code="$(put_json_file "/api/v2/extendedAgent/agents/$name" "$body")"
  report_result "$code" "Registered: $name" "$name"
}

register_response_plan_file() {
  local yaml_path="$1"
  local code plan_body plan_id handling_agent props body="$TMP_DIR/incident-filter.json"

  [[ -f "$yaml_path" ]] || { warn "  Missing response plan YAML: $yaml_path"; return; }

  plan_body="$("$PYTHON" "$SCRIPT_DIR/build-api.py" incident-filter "$yaml_path" 2>"$TMP_DIR/err")" \
    || { warn "  Could not parse response plan YAML ($yaml_path): $(cat "$TMP_DIR/err")"; return; }

  plan_id="$(jq -r '.id // empty' <<<"$plan_body")"
  handling_agent="$(jq -r '.handlingAgent // "default"' <<<"$plan_body")"
  [[ -n "$plan_id" ]] || { warn "  Response plan YAML missing id: $yaml_path"; return; }
  props="$(jq -c 'del(.id, .name)' <<<"$plan_body")"
  jq -nc --arg name "$plan_id" --argjson props "$props" \
    '{name:$name, type:"IncidentFilter", tags:[], properties:$props}' >"$body"

  code="$(put_json_file "/api/v2/extendedAgent/incidentFilters/${plan_id}" "$body")"
  report_result "$code" "Response plan -> ${handling_agent} (${plan_id})" "$plan_id"
}

configure_incident_platform() {
  local patch_file="$TMP_DIR/incident-platform.json"

  log "Configuring incident platform: AzMonitor"
  jq -n '{properties:{incidentManagementConfiguration:{type:"AzMonitor", connectionName:"azmonitor"}}}' >"$patch_file"

  if az rest --method PATCH \
    --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
    --headers "Content-Type=application/json" \
    --body @"$patch_file" \
    --output none 2>/dev/null; then
    ok "  Incident platform: AzMonitor"
    sleep 30
  else
    warn "  Could not configure incident platform: AzMonitor"
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
  report_result "$code" "Uploaded:$names" "Knowledge base upload"
  echo
}

upload_skills() {
  log "Step 2/4: Uploading skills..."
  local f name code count
  count=0

  for f in .github/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    count=$((count + 1))
    name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" skill "$f" "$TMP_DIR/skill.json")"
    code="$(put_json_file "/api/v2/extendedAgent/skills/${name}" "$TMP_DIR/skill.json")"
    report_result "$code" "Skill: $name" "Skill $name"
  done
  [[ "$count" -gt 0 ]] || warn "  No skill files found under .github/skills/*/SKILL.md"
  echo
}

register_subagents() {
  log "Step 3/4: Registering subagents..."
  local item yaml_path name

  for item in "${SUBAGENTS[@]}"; do
    yaml_path="${item%%:*}"
    name="${item##*:}"
    register_subagent "$yaml_path" "$name"
  done
  echo
}

create_response_plans() {
  log "Step 4/4: Creating response plans..."
  local plan

  for plan in "${RESPONSE_PLANS[@]}"; do
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/azure-monitor/incident-filters/${plan}.yaml"
  done
  echo
}

main() {
  parse_args "$@"
  require_tools
  configure_environment
  load_context_from_terraform

  ok "Agent: $AGENT_ENDPOINT"
  auth
  upload_knowledge_base
  upload_skills
  register_subagents
  configure_incident_platform
  create_response_plans
  ok "Recipe extras applied"
}

main "$@"
