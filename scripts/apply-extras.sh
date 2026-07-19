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
SCENARIO=""
DEPLOY_APPS="true"
ENABLE_SERVICE_NOW_CONNECTOR="false"
TFVARS_FILE=""
AGENT_ID=""
AGENT_ENDPOINT=""
TOKEN=""
CUSTOM_INSTRUCTIONS_FILE=""

ALL_SUBAGENT_NAMES=(
  aks-remediator
  alert-investigator
  incident-orchestrator
  issue-triager
  pim-elevation
  triage-agent
)

ALL_RESPONSE_PLAN_NAMES=(
  aks-critical-errors
  all-incidents
  azmon-sev01
  container-apps-alerts
  orders-api-health-response
  orders-api-errors
  orders-api-latency
  snow-all-incidents
)

ALL_KB_NAMES=(
  github-issue-triage.md
  http-500-errors.md
  incident-report.md
  on-call-handoff.md
  orders-architecture.md
)

ALL_SKILL_NAMES=(
  aks-change-triage-rollback
  containerapps-500-diagnostics
  containerapps-latency-diagnostics
  incident-orchestrator-coordination
  investigate-azure-alerts
  triage-app-errors
)

KB_NAMES=("${ALL_KB_NAMES[@]}")
SKILL_NAMES=("${ALL_SKILL_NAMES[@]}")
SUBAGENT_NAMES=("${ALL_SUBAGENT_NAMES[@]}")
RESPONSE_PLAN_NAMES=(
  all-incidents
)
CUSTOM_INSTRUCTIONS_FILE="recipes/azmon-lawappinsights/custom-instructions/default.txt"

usage() {
  cat <<'EOF'
Usage: bash scripts/apply-extras.sh [ENVIRONMENT]

ENVIRONMENT selects matching Terraform files:
  infra/terraform/backend/ENVIRONMENT.backend.tfvars
  infra/terraform/environments/ENVIRONMENT.tfvars

The selected tfvars file scopes the catalog:
  all environments   -> all skills and scenario-scoped knowledge-base docs
  all scenarios      -> one shared incident response plan
  deploy_apps = true -> Container Apps subagents
  deploy_apps = false -> AKS subagents
  tags.scenario = s2   -> autonomous remediation extras
  tags.scenario = s4   -> alert response issue-triage extras
  tags.scenario = s5   -> PIM elevation audit extras
  enable_service_now_connector = true -> ServiceNow incident platform

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

knowledge_base_path() {
  local name="$1"
  [[ -f "knowledge-base/$name" ]] || die "Missing knowledge-base catalog entry: $name"
  echo "knowledge-base/$name"
}

skill_path() {
  local name="$1"
  [[ -f ".github/skills/$name/SKILL.md" ]] || die "Missing skill catalog entry: $name"
  echo ".github/skills/$name/SKILL.md"
}

require_tools() {
  command -v jq >/dev/null || die "jq not found"
  command -v "$PYTHON" >/dev/null || die "Python not found: $PYTHON"
}

configure_environment() {
  [[ -n "$ENVIRONMENT" ]] || return 0

  local backend_file="backend/${ENVIRONMENT}.backend.tfvars"
  TFVARS_FILE="infra/terraform/environments/${ENVIRONMENT}.tfvars"

  [[ -f "infra/terraform/${backend_file}" ]] || die "Missing Terraform backend config: infra/terraform/${backend_file}"
  [[ -f "$TFVARS_FILE" ]] || die "Missing Terraform environment tfvars: $TFVARS_FILE"

  log "Selecting Terraform environment: $ENVIRONMENT"
  SCENARIO="$(awk -F= '
    /^[[:space:]]*tags[[:space:]]*=/ { in_tags = 1; next }
    in_tags && /^[[:space:]]*}/ { in_tags = 0; next }
    in_tags && /^[[:space:]]*scenario[[:space:]]*=/ {
      gsub(/[ ",]/, "", $2)
      print tolower($2)
      exit
    }
  ' "$TFVARS_FILE")"
  DEPLOY_APPS="$(awk -F= '/^[[:space:]]*deploy_apps[[:space:]]*=/{gsub(/[ "]/, "", $2); print tolower($2); exit}' "$TFVARS_FILE")"
  DEPLOY_APPS="${DEPLOY_APPS:-true}"
  ENABLE_SERVICE_NOW_CONNECTOR="$(awk -F= '/^[[:space:]]*enable_service_now_connector[[:space:]]*=/{gsub(/[ "]/ , "", $2); print tolower($2); exit}' "$TFVARS_FILE")"
  ENABLE_SERVICE_NOW_CONNECTOR="${ENABLE_SERVICE_NOW_CONNECTOR:-false}"
  [[ -n "$SCENARIO" ]] && log "Detected scenario scope: $SCENARIO"
  log "Detected runtime scope: $( [[ "$DEPLOY_APPS" == "true" ]] && echo "Container Apps" || echo "AKS" )"
  log "Detected incident platform: $( [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]] && echo "ServiceNow" || echo "AzMonitor" )"
  terraform -chdir=infra/terraform init -reconfigure -backend-config="$backend_file" >/dev/null
}

configure_catalog_scope() {
  if [[ -z "$ENVIRONMENT" ]]; then
    log "No environment selected; applying full recipe extras catalog."
    return 0
  fi

  case "$DEPLOY_APPS" in
    true|false) ;;
    *) die "Unsupported deploy_apps value '$DEPLOY_APPS' in $TFVARS_FILE. Expected true or false." ;;
  esac

  case "$ENABLE_SERVICE_NOW_CONNECTOR" in
    true|false) ;;
    *) die "Unsupported enable_service_now_connector value '$ENABLE_SERVICE_NOW_CONNECTOR' in $TFVARS_FILE. Expected true or false." ;;
  esac

  case "$SCENARIO" in
    ""|s1|s2|s3|s4|s5) ;;
    *) die "Unsupported scenario scope '$SCENARIO' in $TFVARS_FILE. Supported values: s1, s2, s3, s4, s5." ;;
  esac

  SUBAGENT_NAMES=(
    incident-orchestrator
    alert-investigator
  )
  RESPONSE_PLAN_NAMES=(
    all-incidents
  )

  if [[ "$DEPLOY_APPS" == "true" ]]; then
    log "Including Container Apps incident catalog from deploy_apps=true."
    SUBAGENT_NAMES+=(
      triage-agent
    )
  else
    log "Including AKS incident catalog from deploy_apps=false."
    SUBAGENT_NAMES+=(
      aks-remediator
    )
  fi

  case "$SCENARIO" in
    s2)
      log "Including S2 autonomous remediation knowledge base from tags.scenario=s2."
      KB_NAMES=(
        http-500-errors.md
        orders-architecture.md
        incident-report.md
      )
      SKILL_NAMES=(
        incident-orchestrator-coordination
        investigate-azure-alerts
        containerapps-500-diagnostics
        containerapps-latency-diagnostics
      )
      ;;
    s4)
      log "Including S4 alert response issue-triage catalog from tags.scenario=s4."
      SUBAGENT_NAMES+=(
        issue-triager
      )
      ;;
    s5)
      log "Including S5 PIM elevation audit catalog from tags.scenario=s5."
      SUBAGENT_NAMES+=(
        pim-elevation
      )
      ;;
    "")
      log "No scenario-specific extras requested."
      ;;
  esac

  local scenario_instructions="recipes/azmon-lawappinsights/custom-instructions/${SCENARIO}.txt"
  if [[ -n "$SCENARIO" && -f "$scenario_instructions" ]]; then
    CUSTOM_INSTRUCTIONS_FILE="$scenario_instructions"
    log "Including scenario custom instructions: $CUSTOM_INSTRUCTIONS_FILE"
  else
    log "Including default custom instructions: $CUSTOM_INSTRUCTIONS_FILE"
  fi
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

delete_resource() {
  local path="$1" name="$2"
  local code
  code="$(api DELETE "$path")"
  case "$code" in
    200|202|204|404) ok "  Out-of-scope removed or absent: $name" ;;
    *) warn "  Could not remove out-of-scope $name; HTTP $code: $(response_summary)" ;;
  esac
}

contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

subagent_path() {
  case "$1" in
    alert-investigator) echo "recipes/azmon-lawappinsights/agents/alert-investigator.yaml" ;;
    aks-remediator) echo "recipes/azmon-lawappinsights/agents/aks-remediator.yaml" ;;
    incident-orchestrator) echo "recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml" ;;
    issue-triager) echo "recipes/azmon-lawappinsights/agents/issue-triager.yaml" ;;
    pim-elevation) echo "recipes/azmon-lawappinsights/agents/pim-elevation-agent.yaml" ;;
    triage-agent) echo "recipes/azmon-lawappinsights/agents/triage-agent.yaml" ;;
    *) die "Unknown subagent catalog entry: $1" ;;
  esac
}

register_subagent() {
  local yaml_path="$1" name="$2"
  local body="$TMP_DIR/agent.json" code

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml_path" >"$body" 2>"$TMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TMP_DIR/err")"; return; }

  if [[ -f "$CUSTOM_INSTRUCTIONS_FILE" ]]; then
    jq --rawfile instructions "$CUSTOM_INSTRUCTIONS_FILE" \
      '.properties.instructions = ((.properties.instructions // "") + "\n\n" + $instructions)' \
      "$body" >"$TMP_DIR/agent-with-instructions.json"
    mv "$TMP_DIR/agent-with-instructions.json" "$body"
  fi

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
  local platform_type="AzMonitor"
  local connection_name="azmonitor"

  if [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]]; then
    platform_type="ServiceNow"
    connection_name="servicenow"
  fi

  log "Configuring incident platform: $platform_type"
  jq -n --arg type "$platform_type" --arg connectionName "$connection_name" \
    '{properties:{incidentManagementConfiguration:{type:$type, connectionName:$connectionName}}}' >"$patch_file"

  if az rest --method PATCH \
    --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
    --headers "Content-Type=application/json" \
    --body @"$patch_file" \
    --output none 2>/dev/null; then
    ok "  Incident platform: $platform_type"
    sleep 30
  else
    warn "  Could not configure incident platform: $platform_type"
  fi
}

upload_knowledge_base() {
  log "Step 1/4: Uploading knowledge base..."
  local upload names name f code
  upload=(-F triggerIndexing=true)
  names=""

  for name in "${KB_NAMES[@]}"; do
    f="$(knowledge_base_path "$name")"
    upload+=(-F "files=@${f};type=text/plain")
    names+=" $name"
  done

  code="$(api POST /api/v1/AgentMemory/upload "${upload[@]}")"
  report_result "$code" "Uploaded:$names" "Knowledge base upload"
  echo
}

upload_skills() {
  log "Step 2/4: Uploading skills..."
  local f name code

  for name in "${SKILL_NAMES[@]}"; do
    f="$(skill_path "$name")"
    name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" skill "$f" "$TMP_DIR/skill.json")"
    code="$(put_json_file "/api/v2/extendedAgent/skills/${name}" "$TMP_DIR/skill.json")"
    report_result "$code" "Skill: $name" "Skill $name"
  done
  echo
}

cleanup_out_of_scope_skills() {
  log "Cleaning up out-of-scope skills..."
  local name

  for name in "${ALL_SKILL_NAMES[@]}"; do
    contains "$name" "${SKILL_NAMES[@]}" && continue
    delete_resource "/api/v2/extendedAgent/skills/${name}" "Skill: $name"
  done
  echo
}

register_subagents() {
  log "Step 3/4: Registering subagents..."
  local name

  for name in "${SUBAGENT_NAMES[@]}"; do
    register_subagent "$(subagent_path "$name")" "$name"
  done
  echo
}

cleanup_out_of_scope_subagents() {
  log "Cleaning up out-of-scope subagents..."
  local name

  for name in "${ALL_SUBAGENT_NAMES[@]}"; do
    contains "$name" "${SUBAGENT_NAMES[@]}" && continue
    delete_resource "/api/v2/extendedAgent/agents/${name}" "Subagent: $name"
  done
  echo
}

create_response_plans() {
  log "Step 4/4: Creating response plans..."
  local plan incident_platform_dir="azure-monitor"

  if [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]]; then
    incident_platform_dir="servicenow"
  fi

  for plan in "${RESPONSE_PLAN_NAMES[@]}"; do
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/${incident_platform_dir}/incident-filters/${plan}.yaml"
  done
  echo
}

cleanup_out_of_scope_response_plans() {
  log "Cleaning up out-of-scope response plans..."
  local plan

  for plan in "${ALL_RESPONSE_PLAN_NAMES[@]}"; do
    contains "$plan" "${RESPONSE_PLAN_NAMES[@]}" && continue
    delete_resource "/api/v2/extendedAgent/incidentFilters/${plan}" "Response plan: $plan"
  done
  echo
}

main() {
  parse_args "$@"
  require_tools
  configure_environment
  configure_catalog_scope
  load_context_from_terraform

  ok "Agent: $AGENT_ENDPOINT"
  auth
  upload_knowledge_base
  upload_skills
  cleanup_out_of_scope_skills
  register_subagents
  cleanup_out_of_scope_subagents
  configure_incident_platform
  create_response_plans
  cleanup_out_of_scope_response_plans
  ok "Recipe extras applied"
}

main "$@"
