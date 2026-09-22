# shellcheck shell=bash
# shellcheck disable=SC2034  # every array here is consumed by the sourcing script
ALL_SUBAGENT_NAMES=(
  aks-remediator
  aks-triage-agent
  alert-investigator
  incident-comms-agent
  incident-orchestrator
  incident-summary-agent
  issue-triager
  pim-elevation
  triage-agent
)

ALL_KB_NAMES=(
  aks-network-connectivity.md
  aks-pod-failures.md
  aks-resource-exhaustion.md
  github-issue-triage.md
  http-500-errors.md
  incident-report.md
  on-call-handoff.md
  orders-architecture.md
)

ALL_SKILL_NAMES=(
  aks-change-triage-rollback
  azure-cost
  azure-kubernetes
  containerapps-500-diagnostics
  containerapps-latency-diagnostics
  evidence-before-after
  incident-orchestrator-coordination
  investigate-azure-alerts
  servicenow-incident-update
  triage-app-errors
)

# The single source of truth for which scenarios exist and what runtime each
# targets. apply-extras.sh resolves the runtime from here, so adding a scenario
# is one line rather than edits across three files. Deliberately a case rather
# than an associative array: those need bash 4, and this has to run on macOS too.
ALL_SCENARIOS="s1 s2 s3 s4 s5 s6"

scenario_runtime() {
  case "$1" in
    s1)    echo containerapps ;;
    s2)    echo webapp ;;
    s3)    echo aks ;;
    s4)    echo webapp ;;
    s5)    echo none ;;
    s6)    echo containerapps ;;
    *)     return 1 ;;
  esac
}

ALL_TOOL_NAMES=(
  LookupServiceNowIncident
  UpdateServiceNowIncident
  UploadServiceNowAttachment
)

ALL_HOOK_NAMES=(
  deny-prod-deletes
  require-approval-for-restarts
  s2-require-approval-for-deployment-changes
)

ALL_COMMON_PROMPT_NAMES=(
  investigation-guidelines
  s2-orders-api-runtime
  s3-aks-incident
  s4-alert-response
  safety-rules
)

KB_NAMES=("${ALL_KB_NAMES[@]}")
SKILL_NAMES=("${ALL_SKILL_NAMES[@]}")
TOOL_NAMES=("${ALL_TOOL_NAMES[@]}")

# Applied in every scenario. Scenario branches add to these rather than restating them.
DEFAULT_HOOK_NAMES=(
  deny-prod-deletes
  require-approval-for-restarts
)
DEFAULT_COMMON_PROMPT_NAMES=(
  investigation-guidelines
  safety-rules
)
HOOK_NAMES=("${ALL_HOOK_NAMES[@]}")
COMMON_PROMPT_NAMES=("${DEFAULT_COMMON_PROMPT_NAMES[@]}")
SUBAGENT_NAMES=("${ALL_SUBAGENT_NAMES[@]}")
RESPONSE_PLAN_NAMES=(
  all-incidents
)

catalog_path() {
  local label="$1" f="$2"
  [[ -f "$f" ]] || die "Missing $label catalog entry: $f"
  echo "$f"
}

knowledge_base_path() { catalog_path knowledge-base "knowledge-base/$1"; }
skill_path()          { catalog_path skill ".github/skills/$1/SKILL.md"; }
hook_path()           { catalog_path hook "recipes/azmon-lawappinsights/config/hooks/$1.yaml"; }
common_prompt_path() {
  local name="$1"
  if [[ "$name" == "s2-orders-api-runtime" ]]; then
    catalog_path "common prompt" "recipes/azmon-lawappinsights/config/common-prompts/${name}-${RUNTIME_STACK}.yaml"
    return
  fi
  catalog_path "common prompt" "recipes/azmon-lawappinsights/config/common-prompts/$name.yaml"
}
repo_path()           { catalog_path repo "recipes/azmon-lawappinsights/config/repos/$1.yaml"; }
tool_path()           { catalog_path tool "recipes/alert-response-incident-operations/config/tools/$1/$1.yaml"; }

subagent_path() {
  case "$1" in
    alert-investigator) echo "recipes/azmon-lawappinsights/agents/alert-investigator.yaml" ;;
    aks-remediator) echo "recipes/azmon-lawappinsights/agents/aks-remediator.yaml" ;;
    aks-triage-agent) echo "recipes/alert-response-incident-operations/config/subagents/aks-triage-agent.yaml" ;;
    incident-comms-agent) echo "recipes/alert-response-incident-operations/config/subagents/incident-comms-agent.yaml" ;;
    incident-orchestrator) echo "recipes/azmon-lawappinsights/agents/orchestrator-agent.yaml" ;;
    incident-summary-agent) echo "recipes/alert-response-incident-operations/config/subagents/incident-summary-agent.yaml" ;;
    issue-triager) echo "recipes/azmon-lawappinsights/agents/issue-triager.yaml" ;;
    pim-elevation) echo "recipes/azmon-lawappinsights/agents/pim-elevation-agent.yaml" ;;
    triage-agent) echo "recipes/azmon-lawappinsights/agents/triage-agent.yaml" ;;
    *) die "Unknown subagent catalog entry: $1" ;;
  esac
}

configure_catalog_scope() {
  if [[ -z "$ENVIRONMENT" ]]; then
    log "No environment selected; applying full recipe extras catalog."
    return 0
  fi

  case "$RUNTIME_STACK" in
    containerapps|aks|webapp|none) ;;
    *) die "Unsupported runtime_stack value '$RUNTIME_STACK' in $TFVARS_FILE. Expected containerapps, aks, webapp, or none." ;;
  esac

  case "$ENABLE_SERVICE_NOW_CONNECTOR" in
    true|false) ;;
    *) die "Unsupported enable_service_now_connector value '$ENABLE_SERVICE_NOW_CONNECTOR' in $TFVARS_FILE. Expected true or false." ;;
  esac

  if [[ -n "$SCENARIO" ]] && ! scenario_runtime "$SCENARIO" >/dev/null; then
    die "Unsupported scenario scope '$SCENARIO' in $TFVARS_FILE. Supported values: $ALL_SCENARIOS"
  fi

  SUBAGENT_NAMES=(
    incident-orchestrator
    alert-investigator
  )
  RESPONSE_PLAN_NAMES=(
    all-incidents
  )
  # Custom PythonTools are opt-in per scenario; only S3 writes back to ServiceNow.
  TOOL_NAMES=()
  HOOK_NAMES=("${DEFAULT_HOOK_NAMES[@]}")
  COMMON_PROMPT_NAMES=("${DEFAULT_COMMON_PROMPT_NAMES[@]}")

  case "$RUNTIME_STACK" in
    none)
      log "Skipping runtime subagents for runtime_stack=none."
      ;;
    webapp)
      if [[ "$SCENARIO" == "s2" ]]; then
        log "Including App Service incident catalog for S2."
        SUBAGENT_NAMES+=(
          triage-agent
        )
      else
        log "Skipping runtime subagents for runtime_stack=webapp."
      fi
      ;;
    containerapps)
      log "Including Container Apps incident catalog from runtime_stack=containerapps."
      SUBAGENT_NAMES+=(
        triage-agent
      )
      ;;
    aks)
      log "Including AKS incident catalog from runtime_stack=aks."
      SUBAGENT_NAMES+=(
        aks-remediator
      )
      ;;
  esac

  case "$SCENARIO" in
    s3)
      log "Including S3 high-severity AKS incident catalog from scenario=s3."
      SUBAGENT_NAMES=(
        aks-triage-agent
        incident-summary-agent
        incident-comms-agent
      )
      if [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]]; then
        RESPONSE_PLAN_NAMES=(
          aks-incidents
        )
      else
        RESPONSE_PLAN_NAMES=(
          aks-critical-errors
        )
      fi
      KB_NAMES=(
        aks-network-connectivity.md
        aks-pod-failures.md
        aks-resource-exhaustion.md
        incident-report.md
        on-call-handoff.md
        orders-architecture.md
      )
      SKILL_NAMES=(
        aks-change-triage-rollback
        azure-cost
        azure-kubernetes
        evidence-before-after
        incident-orchestrator-coordination
        investigate-azure-alerts
        servicenow-incident-update
      )
      # S3 is the only scenario that reads from and writes back to an incident record.
      TOOL_NAMES=(
        LookupServiceNowIncident
        UpdateServiceNowIncident
        UploadServiceNowAttachment
      )
      COMMON_PROMPT_NAMES+=(
        s3-aks-incident
      )
      ;;
    s2)
      log "Including S2 autonomous remediation knowledge base from scenario=s2."
      RESPONSE_PLAN_NAMES=(
        s2-orders-api-runtime
      )
      KB_NAMES=(
        http-500-errors.md
        orders-architecture.md
        incident-report.md
      )
      SKILL_NAMES=(
        incident-orchestrator-coordination
        investigate-azure-alerts
        triage-app-errors
      )
      if [[ "$RUNTIME_STACK" == "containerapps" ]]; then
        SKILL_NAMES+=(
          containerapps-500-diagnostics
          containerapps-latency-diagnostics
        )
      fi
      COMMON_PROMPT_NAMES+=(
        s2-orders-api-runtime
      )
      # S2 runs Autonomous with High access, so deployment writes need a gate.
      HOOK_NAMES+=(
        s2-require-approval-for-deployment-changes
      )
      ;;
    s4)
      log "Including S4 alert response incident-operations catalog from scenario=s4."
      # S4 reuses the alert-response-incident-operations handoff chain, swapping
      # the AKS triage head for alert-investigator (already in the base set).
      SUBAGENT_NAMES+=(
        incident-summary-agent
        incident-comms-agent
        issue-triager
      )
      COMMON_PROMPT_NAMES+=(
        s4-alert-response
      )
      ;;
    s5)
      log "Including S5 PIM elevation audit catalog from scenario=s5."
      SUBAGENT_NAMES+=(
        pim-elevation
      )
      ;;
    "")
      log "No scenario-specific extras requested."
      ;;
  esac

  log "Common prompts: ${COMMON_PROMPT_NAMES[*]}"
  log "Hooks: ${HOOK_NAMES[*]}"

  [[ ${#RESPONSE_PLAN_NAMES[@]} -eq 1 ]] \
    || die "Scenario '${SCENARIO:-unscoped}' must select exactly one response plan; selected: ${RESPONSE_PLAN_NAMES[*]:-none}"
}