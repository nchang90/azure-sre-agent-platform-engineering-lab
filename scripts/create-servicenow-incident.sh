#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }

ENVIRONMENT="${1:-}"
SHORT_DESCRIPTION="${2:-}"
DESCRIPTION="${3:-}"

if [[ -z "$ENVIRONMENT" || -z "$SHORT_DESCRIPTION" ]]; then
  echo "Usage: bash scripts/create-servicenow-incident.sh ENVIRONMENT SHORT_DESCRIPTION [DESCRIPTION]" >&2
  exit 2
fi

TFVARS_FILE="infra/terraform/environments/${ENVIRONMENT}.tfvars"
[[ -f "$TFVARS_FILE" ]] || { warn "Missing tfvars file: $TFVARS_FILE"; exit 0; }

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

enabled="$(tfvar enable_service_now_connector)"
enabled="${enabled,,}"
if [[ "$enabled" != "true" ]]; then
  log "ServiceNow is not enabled for $ENVIRONMENT; skipping incident creation."
  exit 0
fi

instance="$(tfvar service_now_instance)"
username="$(tfvar service_now_username)"
password="${TF_VAR_service_now_password:-${SERVICENOW_PASSWORD:-}}"

if [[ -z "$instance" || -z "$username" || -z "$password" ]]; then
  warn "ServiceNow instance, username, or password is missing; skipping incident creation."
  exit 0
fi

body="$(jq -n \
  --arg short_description "$SHORT_DESCRIPTION" \
  --arg description "$DESCRIPTION" \
  '{
    short_description: $short_description,
    description: $description,
    work_notes: $description,
    category: "inquiry",
    subcategory: "monitoring",
    contact_type: "monitoring",
    priority: "2",
    impact: "2",
    urgency: "2"
  }')"

log "Creating ServiceNow incident for AKS deployment failure..."
response="$(curl -sS \
  --fail-with-body \
  --user "${username}:${password}" \
  --header "Accept: application/json" \
  --header "Content-Type: application/json" \
  --data "$body" \
  "${instance%/}/api/now/table/incident")"

number="$(jq -r '.result.number // empty' <<<"$response")"
sys_id="$(jq -r '.result.sys_id // empty' <<<"$response")"

if [[ -n "$number" ]]; then
  log "Created ServiceNow incident: $number ($sys_id)"
  log "ServiceNow incident URL: ${instance%/}/nav_to.do?uri=incident.do?sys_id=${sys_id}"
else
  warn "ServiceNow incident response did not include an incident number."
fi
