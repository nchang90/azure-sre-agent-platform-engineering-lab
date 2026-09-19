# shellcheck shell=bash
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

# shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
ALL_RESPONSE_PLAN_NAMES=(
  aks-incidents
  aks-pod-urgent
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
  rca-analysis
  servicenow-incident-update
  triage-app-errors
)

ALL_TOOL_NAMES=(
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
HOOK_NAMES=("${ALL_HOOK_NAMES[@]}")
# Lab-wide prompts apply in every scenario; scenario-scoped ones are added below.
COMMON_PROMPT_NAMES=(
  investigation-guidelines
  safety-rules
)
SUBAGENT_NAMES=("${ALL_SUBAGENT_NAMES[@]}")
RESPONSE_PLAN_NAMES=(
  all-incidents
)

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

tool_path() {
  local name="$1"
  local f="recipes/alert-response-incident-operations/config/tools/$name/$name.yaml"
  [[ -f "$f" ]] || die "Missing tool catalog entry: $name"
  echo "$f"
}

hook_path() {
  local name="$1"
  local f="recipes/azmon-lawappinsights/config/hooks/$name.yaml"
  [[ -f "$f" ]] || die "Missing hook catalog entry: $name"
  echo "$f"
}

common_prompt_path() {
  local name="$1"
  local f="recipes/azmon-lawappinsights/config/common-prompts/$name.yaml"
  [[ -f "$f" ]] || die "Missing common prompt catalog entry: $name"
  echo "$f"
}

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

  case "$SCENARIO" in
    ""|s1|s2|s3|s4|s5|s6) ;;
    *) die "Unsupported scenario scope '$SCENARIO' in $TFVARS_FILE. Supported values: s1, s2, s3, s4, s5, s6." ;;
  esac

  SUBAGENT_NAMES=(
    incident-orchestrator
    alert-investigator
  )
  RESPONSE_PLAN_NAMES=(
    all-incidents
  )
  # Custom PythonTools are opt-in per scenario; only S3 writes back to ServiceNow.
  TOOL_NAMES=()
  # Global guardrails apply in every scenario; S2 adds a deployment-specific one.
  HOOK_NAMES=(
    deny-prod-deletes
    require-approval-for-restarts
  )
  COMMON_PROMPT_NAMES=(
    investigation-guidelines
    safety-rules
  )

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
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      RESPONSE_PLAN_NAMES=(
        aks-critical-errors
      )
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
        rca-analysis
        servicenow-incident-update
      )
      # S3 is the only scenario that writes back to an incident record.
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      TOOL_NAMES=(
        UpdateServiceNowIncident
        UploadServiceNowAttachment
      )
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      COMMON_PROMPT_NAMES+=(
        s3-aks-incident
      )
      ;;
    s2)
      log "Including S2 autonomous remediation knowledge base from scenario=s2."
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
        rca-analysis
        triage-app-errors
      )
      if [[ "$RUNTIME_STACK" == "containerapps" ]]; then
        SKILL_NAMES+=(
          containerapps-500-diagnostics
          containerapps-latency-diagnostics
        )
      fi
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
      COMMON_PROMPT_NAMES+=(
        s2-orders-api-runtime
      )
      # S2 runs Autonomous with High access, so deployment writes need a gate.
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
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
      # shellcheck disable=SC2034  # Used by apply-extras.sh after sourcing this file
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
}