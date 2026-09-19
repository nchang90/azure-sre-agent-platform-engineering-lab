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

# Step numbers are derived so inserting a step does not mean renumbering the rest.
STEP=0
STEP_TOTAL=8
step() { STEP=$((STEP + 1)); log "Step $STEP/$STEP_TOTAL: $*"; }

ENVIRONMENT=""
SCENARIO=""
TFVARS_FILE=""
AGENT_ID=""
AGENT_ENDPOINT=""
SCOPED_PROMPTS_JSON="[]"
SCOPED_SUBAGENTS_JSON="[]"
TOKEN=""

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
  scenario = s1..s6        -> primary scenario selector
  S2 runtime         -> deployed Terraform runtime_stack (webapp or containerapps)
  fixed runtimes     -> s1=containerapps, s3=aks, s4=webapp, s5=none

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
      gsub(/^[[:space:]"]+|[[:space:]"]+$/, "", value)
      print value
      exit
    }
  ' "$TFVARS_FILE"
}

tfvar_bool() {
  local key="$1" default_value="$2" value
  value="$(tfvar "$key")"
  value="${value:-$default_value}"
  printf '%s\n' "$value" | tr '[:upper:]' '[:lower:]'
}

resolve_runtime_stack() {
  local scenario="$1" runtime=""

  if [[ -n "${RUNTIME_STACK_OVERRIDE:-}" ]]; then
    printf '%s\n' "$RUNTIME_STACK_OVERRIDE"
    return
  fi

  if [[ "$scenario" == "s2" ]]; then
    runtime="$(terraform -chdir=infra/terraform output -raw runtime_stack 2>/dev/null | tr -d '\r' || true)"
    if [[ "$runtime" == "webapp" || "$runtime" == "containerapps" ]]; then
      printf '%s\n' "$runtime"
      return
    fi
  fi

  runtime="${runtime:-$(scenario_runtime "$scenario")}" \
    || die "Unsupported scenario '$scenario' in $TFVARS_FILE. Expected one of: $ALL_SCENARIOS"
  printf '%s\n' "$runtime"
}

configure_environment() {
  [[ -n "$ENVIRONMENT" ]] || return 0

  local backend_file="backend/${ENVIRONMENT}.backend.tfvars"
  TFVARS_FILE="infra/terraform/environments/${ENVIRONMENT}.tfvars"

  [[ -f "infra/terraform/${backend_file}" ]] || die "Missing Terraform backend config: infra/terraform/${backend_file}"
  [[ -f "$TFVARS_FILE" ]] || die "Missing Terraform environment tfvars: $TFVARS_FILE"

  log "Selecting Terraform environment: $ENVIRONMENT"
  SCENARIO="$(tfvar scenario | tr '[:upper:]' '[:lower:]')"
  [[ -n "$SCENARIO" ]] || die "scenario is required in $TFVARS_FILE (expected s1, s2, s3, s4, or s5)."
  terraform -chdir=infra/terraform init -reconfigure -backend-config="$backend_file" >/dev/null
  RUNTIME_STACK="$(resolve_runtime_stack "$SCENARIO")"
  case "$RUNTIME_STACK" in
    containerapps|aks|webapp|none) ;;
    *) die "Unsupported runtime stack override: $RUNTIME_STACK" ;;
  esac
  [[ -n "$SCENARIO" ]] && log "Detected scenario scope: $SCENARIO"
  case "$RUNTIME_STACK" in
    none) log "Detected runtime scope: none (monitoring-only mode)" ;;
    containerapps) log "Detected runtime scope: Container Apps" ;;
    aks) log "Detected runtime scope: AKS" ;;
    webapp) log "Detected runtime scope: App Service" ;;
  esac
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

is_success_http() {
  case "$1" in
    200|201|202|204|409) return 0 ;;
    *) return 1 ;;
  esac
}

auth() {
  TOKEN="$(az account get-access-token --resource https://azuresre.dev --query accessToken -o tsv 2>/dev/null)" \
    || die "Failed to get access token — run 'az login' first"
  [[ -n "$TOKEN" ]] || die "Received empty Azure access token for https://azuresre.dev"
}

current_incident_platform_type() {
  { az rest --method GET \
      --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
      --query "properties.incidentManagementConfiguration.type" \
      -o tsv 2>/dev/null || true; } | tr -d '\r'
}

wait_for_incident_platform() {
  local expected_type="$1" attempts="${2:-8}" delay_seconds="${3:-15}" attempt actual_type

  for attempt in $(seq 1 "$attempts"); do
    actual_type="$(current_incident_platform_type)"
    if [[ "$actual_type" == "$expected_type" ]]; then
      ok "  Incident platform ready: $expected_type"
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]]; then
      log "Waiting for incident platform '$expected_type' (current: ${actual_type:-None})..."
      sleep "$delay_seconds"
    fi
  done

  return 1
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

workspace_mode_handoffs_unsupported() {
  [[ -s "$RESP" ]] && grep -q "New agent-to-agent handoffs are not supported in workspace mode" "$RESP"
}

remove_agent_handoffs_for_workspace_mode() {
  local body="$1"
  jq '
    .properties.handoffs = [] |
    .properties.instructions = ((.properties.instructions // "") + "\n\nWorkspace mode fallback: agent-to-agent handoffs are unavailable in this environment. Complete any downstream handoff responsibilities yourself and return the final output expected from this workflow.")
  ' "$body" >"$TMP_DIR/agent-workspace-fallback.json"
  mv "$TMP_DIR/agent-workspace-fallback.json" "$body"
}

register_subagent() {
  local yaml_path="$1" name="$2"
  local body="$TMP_DIR/agent.json" code

  "$PYTHON" "$SCRIPT_DIR/build-api.py" agent "$yaml_path" >"$body" 2>"$TMP_DIR/err" \
    || { warn "  $name: YAML conversion failed — $(cat "$TMP_DIR/err")"; return; }

  # Scenario guidance is attached by reference as common prompts, not pasted into
  # each agent's instructions. Handoffs are filtered to subagents this scenario
  # actually registers, so an agent YAML can declare its full chain honestly
  # without pointing at an agent cleanup_out_of_scope is about to delete.
  jq --argjson prompts "$SCOPED_PROMPTS_JSON" --argjson registered "$SCOPED_SUBAGENTS_JSON" \
    '.properties.commonPrompts = ((.properties.commonPrompts // []) + $prompts | unique)
     | .properties.handoffs = [(.properties.handoffs // [])[] | select(IN($registered[]))]' \
    "$body" >"$TMP_DIR/agent-scoped.json"
  mv "$TMP_DIR/agent-scoped.json" "$body"

  code="$(put_json_file "/api/v2/extendedAgent/agents/$name" "$body")"
  if [[ "$code" == "400" ]] && workspace_mode_handoffs_unsupported; then
    warn "  $name does not support handoffs in workspace mode; retrying without handoffs."
    remove_agent_handoffs_for_workspace_mode "$body"
    code="$(put_json_file "/api/v2/extendedAgent/agents/$name" "$body")"
  fi
  report_result "$code" "Registered: $name" "$name"
}

register_response_plan_file() {
  local yaml_path="$1"
  local code plan_body plan_id handling_agent expected_platform props body="$TMP_DIR/incident-filter.json" attempt summary

  [[ -f "$yaml_path" ]] || die "Missing response plan YAML: $yaml_path"

  plan_body="$("$PYTHON" "$SCRIPT_DIR/build-api.py" incident-filter "$yaml_path" 2>"$TMP_DIR/err")" \
    || die "Could not parse response plan YAML ($yaml_path): $(cat "$TMP_DIR/err")"

  plan_id="$(jq -r '.id // empty' <<<"$plan_body")"
  handling_agent="$(jq -r '.handlingAgent // "default"' <<<"$plan_body")"
  expected_platform="$(jq -r '.incidentPlatform // empty' <<<"$plan_body")"
  [[ -n "$plan_id" ]] || die "Response plan YAML missing id: $yaml_path"
  props="$(jq -c 'del(.id, .name)' <<<"$plan_body")"
  jq -nc --arg name "$plan_id" --argjson props "$props" \
    '{name:$name, type:"IncidentFilter", tags:[], properties:$props}' >"$body"

  for attempt in 1 2 3 4; do
    code="$(put_json_file "/api/v2/extendedAgent/incidentFilters/${plan_id}" "$body")"
    if is_success_http "$code"; then
      ok "  Response plan -> ${handling_agent} (${plan_id})"
      return 0
    fi

    summary="$(response_summary)"
    if [[ "$attempt" -lt 4 && "$code" == "400" && -n "$expected_platform" && "$summary" == *"Incident platform '${expected_platform}' does not match configured incident management type"* ]]; then
      local actual_type
      actual_type="$(current_incident_platform_type)"
      if [[ -n "$actual_type" && "$actual_type" != "None" && "$actual_type" != "$expected_platform" ]]; then
        die "Response plan '${plan_id}' expects incident platform '${expected_platform}', but the agent is configured for '${actual_type}'."
      fi
      warn "  Response plan '${plan_id}' is waiting for incident platform '${expected_platform}' to finish initializing."
      wait_for_incident_platform "$expected_platform" 4 15 || true
      sleep 15
      continue
    fi

    die "Response plan '${plan_id}' registration failed with HTTP $code: $summary"
  done
}

configure_incident_platform() {
  local patch_file="$TMP_DIR/incident-platform.json"
  local platform_type="AzMonitor"
  local connection_name="azmonitor"

  log "Configuring incident platform: $platform_type"
  jq -n --arg type "$platform_type" --arg connectionName "$connection_name" \
    '{properties:{incidentManagementConfiguration:{type:$type, connectionName:$connectionName}}}' >"$patch_file"

  if az rest --method PATCH \
    --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
    --headers "Content-Type=application/json" \
    --body @"$patch_file" \
    --output none 2>/dev/null; then
    ok "  Incident platform: $platform_type"
    wait_for_incident_platform "$platform_type" 8 15 || warn "  Incident platform has not reported ready yet; response plan registration will retry if needed."
  else
    warn "  Could not configure incident platform: $platform_type"
  fi
}

upload_knowledge_base() {
  step "Uploading knowledge base..."
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

# Every envelope-shaped collection uploads the same way: resolve the catalog path,
# convert to an API envelope, PUT it, report. Kinds differ only in the five values
# passed in. Uses the same nameref style as cleanup_out_of_scope.
upload_collection() {
  local label="$1" mode="$2" path_fn="$3" api_prefix="$4"
  local -n _names="$5"
  local entry f name code

  for entry in "${_names[@]}"; do
    f="$("$path_fn" "$entry")"
    if ! name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" "$mode" "$f" "$TMP_DIR/envelope.json" 2>"$TMP_DIR/err")"; then
      warn "  $entry: conversion failed — $(tr '\n' ' ' <"$TMP_DIR/err")"
      continue
    fi
    code="$(put_json_file "${api_prefix}/${name}" "$TMP_DIR/envelope.json")"
    report_result "$code" "$label: $name" "$label $name"
  done
  # Tool envelopes carry live credentials; never leave one on disk.
  rm -f "$TMP_DIR/envelope.json"
  echo
}

upload_common_prompts() {
  step "Uploading common prompts..."
  upload_collection "Common prompt" common-prompt common_prompt_path \
    /api/v2/extendedAgent/commonprompts COMMON_PROMPT_NAMES
}

upload_hooks() {
  step "Uploading hooks..."
  upload_collection "Hook" hook hook_path /api/v2/extendedAgent/hooks HOOK_NAMES
}

# Resolve the repository to connect: GITHUB_REPOSITORY is set automatically in
# GitHub Actions; fall back to the origin remote for local runs.
resolve_github_repository() {
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    echo "$GITHUB_REPOSITORY"
    return 0
  fi
  local origin
  origin="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$origin" ]] || return 1
  origin="${origin%.git}"
  origin="${origin#git@github.com:}"
  origin="${origin#https://github.com/}"
  echo "$origin"
}

register_repo() {
  step "Connecting GitHub repository..."
  local src repo staged name code
  src="$(repo_path github-repo)"

  repo="$(resolve_github_repository || true)"
  if [[ -z "$repo" ]]; then
    warn "  Could not resolve a repository (set GITHUB_REPOSITORY or add an origin remote); skipping."
    echo
    return
  fi

  staged="$TMP_DIR/github-repo.yaml"
  sed "s|{{githubRepo}}|${repo}|g" "$src" >"$staged"

  name="$("$PYTHON" "$SCRIPT_DIR/build-api.py" repo "$staged" "$TMP_DIR/repo.json")" \
    || { warn "  Repo conversion failed"; echo; return; }

  # Note: this is /api/v2/repos, NOT under /api/v2/extendedAgent.
  code="$(put_json_file "/api/v2/repos/${name}" "$TMP_DIR/repo.json")"
  report_result "$code" "Repo: $name -> $repo" "Repo $name"
  is_success_http "$code" \
    && log "  If the agent cannot read the repo, authorize GitHub once in the portal Repos blade."
  echo
}

# The ServiceNow write-back tools carry literal credentials (the PythonTool
# sandbox cannot read env vars). Without them, drop both the tools and the skill
# that drives them rather than registering a skill whose tools do not exist.
servicenow_configured() {
  [[ -n "${SERVICENOW_URL:-}" && -n "${SERVICENOW_USER:-}" && -n "${SERVICENOW_PASS:-}" ]]
}

drop_servicenow_from_scope() {
  local kept=() name
  for name in "${SKILL_NAMES[@]}"; do
    [[ "$name" == "servicenow-incident-update" ]] || kept+=("$name")
  done
  SKILL_NAMES=("${kept[@]}")
  TOOL_NAMES=()
}

upload_tools() {
  step "Uploading custom tools..."

  # Scenarios other than S3 default to the full skill list, which would otherwise
  # ship servicenow-incident-update with none of the tools it drives.
  if [[ ${#TOOL_NAMES[@]} -eq 0 ]]; then
    log "  No custom tools in scope."
    drop_servicenow_from_scope
    echo
    return
  fi

  if ! servicenow_configured; then
    warn "  SERVICENOW_URL/USER/PASS not set — skipping ServiceNow tools and the servicenow-incident-update skill."
    warn "  See .servicenow.env.sample."
    drop_servicenow_from_scope
    echo
    return
  fi

  upload_collection "Tool" tool tool_path /api/v2/extendedAgent/tools TOOL_NAMES
}

upload_skills() {
  step "Uploading skills..."
  upload_collection "Skill" skill skill_path /api/v2/extendedAgent/skills SKILL_NAMES
}

register_subagents() {
  step "Registering subagents..."
  local name

  # Invariant for the whole run; building them per agent spawned four jq processes each.
  SCOPED_PROMPTS_JSON="$(jq -nc '$ARGS.positional' --args "${COMMON_PROMPT_NAMES[@]}")"
  SCOPED_SUBAGENTS_JSON="$(jq -nc '$ARGS.positional' --args "${SUBAGENT_NAMES[@]}")"

  for name in "${SUBAGENT_NAMES[@]}"; do
    register_subagent "$(subagent_path "$name")" "$name"
  done
  echo
}

create_response_plans() {
  step "Creating response plans..."
  local plan

  for plan in "${RESPONSE_PLAN_NAMES[@]}"; do
    register_response_plan_file "recipes/azmon-lawappinsights/incident-platforms/azure-monitor/incident-filters/${plan}.yaml"
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
  upload_common_prompts
  cleanup_out_of_scope "Common prompt" "/api/v2/extendedAgent/commonprompts" ALL_COMMON_PROMPT_NAMES COMMON_PROMPT_NAMES
  upload_hooks
  cleanup_out_of_scope "Hook" "/api/v2/extendedAgent/hooks" ALL_HOOK_NAMES HOOK_NAMES
  register_repo
  upload_tools
  cleanup_out_of_scope "Tool" "/api/v2/extendedAgent/tools" ALL_TOOL_NAMES TOOL_NAMES
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
