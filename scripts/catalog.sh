# shellcheck shell=bash
ALL_SUBAGENT_NAMES=(
  aks-remediator
  alert-investigator
  incident-orchestrator
  issue-triager
  pim-elevation
  triage-agent
)

# shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
ALL_RESPONSE_PLAN_NAMES=(
  aks-incidents
  aks-critical-errors
  all-incidents
  azmon-sev01
  container-apps-alerts
  orders-api-health-response
  orders-api-errors
  orders-api-latency
  s2-orders-api-runtime
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
    s3)
      log "Including S3 AKS ServiceNow incident catalog from tags.scenario=s3."
      if [[ "$ENABLE_SERVICE_NOW_CONNECTOR" == "true" ]]; then
        # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
        RESPONSE_PLAN_NAMES=(
          aks-incidents
        )
      fi
      KB_NAMES=(
        incident-report.md
        on-call-handoff.md
        orders-architecture.md
      )
      SKILL_NAMES=(
        aks-change-triage-rollback
        incident-orchestrator-coordination
        investigate-azure-alerts
      )
      ;;
    s2)
      log "Including S2 autonomous remediation knowledge base from tags.scenario=s2."
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      RESPONSE_PLAN_NAMES=(
        s2-orders-api-runtime
      )
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      KB_NAMES=(
        http-500-errors.md
        orders-architecture.md
        incident-report.md
      )
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
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