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
ENABLE_SERVICE_NOW_CONNECTOR="false"
SERVICE_NOW_INSTANCE=""
SERVICE_NOW_USERNAME=""
SERVICE_NOW_PASSWORD=""
TFVARS_FILE=""
AGENT_ID=""
AGENT_ENDPOINT=""
TOKEN=""
CUSTOM_INSTRUCTIONS_FILE=""

# shellcheck source=scripts/catalog.sh
source "$SCRIPT_DIR/catalog.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/apply-extras.sh [ENVIRONMENT]

ENVIRONMENT selects matching Terraform files:
  infra/terraform/backend/ENVIRONMENT.backend.tfvars
  infra/terraform/environments/ENVIRONMENT.tfvars

The selected tfvars file scopes the catalog:
  all environments   -> all skills and scenario-scoped knowledge-base docs
  all scenarios      -> one shared incident response plan
  all environments   -> Container Apps subagents
  deploy_aks = true  -> AKS subagents
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

require_tools() {
  command -v jq >/dev/null || die "jq not found"
  command -v "$PYTHON" >/dev/null || die "Python not found: $PYTHON"
}

tfvar() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]\"]+|[[:space:]\"]+$/, "", value)
      print value
      exit
    }
  ' "$TFVARS_FILE"
}

tfvar_bool() {
  local key="$1" default_value="$2" value
  value="$(tfvar "$key")"
  value="${value:-$default_value}"
  echo "${value,,}"
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
  DEPLOY_AKS="$(tfvar_bool deploy_aks false)"
  ENABLE_SERVICE_NOW_CONNECTOR="$(tfvar_bool enable_service_now_connector false)"
  SERVICE_NOW_INSTANCE="$(tfvar service_now_instance)"
  SERVICE_NOW_USERNAME="$(tfvar service_now_username)"
  SERVICE_NOW_PASSWORD="${TF_VAR_service_now_password:-${SERVICENOW_PASSWORD:-}}"
  [[ -n "$SCENARIO" ]] && log "Detected scenario scope: $SCENARIO"
  log "Detected runtime scope: Container Apps$( [[ "$DEPLOY_AKS" == "true" ]] && echo " + AKS" )"
  log "Detected incident platform: $( [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]] && echo "ServiceNow" || echo "AzMonitor" )"
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

delete_resource() {
  local path="$1" name="$2"
  local code
  code="$(api DELETE "$path")"
  case "$code" in
    200|202|204|404) ok "  Out-of-scope removed or absent: $name" ;;
    *) warn "  Could not remove out-of-scope $name; HTTP $code: $(response_summary)" ;;
  esac
}

cleanup_out_of_scope() {
  local label="$1" path_prefix="$2" all_var="$3" selected_var="$4" name
  local -n all_items="$all_var"
  local -n selected_items="$selected_var"

  log "Cleaning up out-of-scope ${label}s..."
  for name in "${all_items[@]}"; do
    contains "$name" "${selected_items[@]}" && continue
    delete_resource "${path_prefix}/${name}" "${label}: $name"
  done
  echo
}

contains() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
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

    [[ -n "$SERVICE_NOW_INSTANCE" ]] || die "service_now_instance is required when enable_service_now_connector=true"
    [[ -n "$SERVICE_NOW_USERNAME" ]] || die "service_now_username is required when enable_service_now_connector=true"
    [[ -n "$SERVICE_NOW_PASSWORD" ]] || die "TF_VAR_service_now_password or SERVICENOW_PASSWORD is required when enable_service_now_connector=true"
  fi

  log "Configuring incident platform: $platform_type"
  if [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]]; then
    jq -n \
      --arg type "$platform_type" \
      --arg connectionName "$connection_name" \
      --arg connectionUrl "$SERVICE_NOW_INSTANCE" \
      --arg endpoint "$SERVICE_NOW_INSTANCE" \
      --arg username "$SERVICE_NOW_USERNAME" \
      --arg password "$SERVICE_NOW_PASSWORD" \
      '{properties:{incidentManagementConfiguration:{type:$type, connectionName:$connectionName, connectionUrl:$connectionUrl, connectionKey:({endpoint:$endpoint, username:$username, password:$password} | tojson)}}}' >"$patch_file"
  else
    jq -n --arg type "$platform_type" --arg connectionName "$connection_name" \
      '{properties:{incidentManagementConfiguration:{type:$type, connectionName:$connectionName}}}' >"$patch_file"
  fi

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

register_subagents() {
  log "Step 3/4: Registering subagents..."
  local name

  for name in "${SUBAGENT_NAMES[@]}"; do
    register_subagent "$(subagent_path "$name")" "$name"
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
  cleanup_out_of_scope "Skill" "/api/v2/extendedAgent/skills" ALL_SKILL_NAMES SKILL_NAMES
  register_subagents
  cleanup_out_of_scope "Subagent" "/api/v2/extendedAgent/agents" ALL_SUBAGENT_NAMES SUBAGENT_NAMES
  configure_incident_platform
  create_response_plans
  cleanup_out_of_scope "Response plan" "/api/v2/extendedAgent/incidentFilters" ALL_RESPONSE_PLAN_NAMES RESPONSE_PLAN_NAMES
  ok "Recipe extras applied"
}

main "$@"
