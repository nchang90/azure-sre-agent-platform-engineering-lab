#!/usr/bin/env bash
set -euo pipefail

step() { echo; echo "▶ $1 — $2"; }
info() { echo "  $*"; }
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }

retry() {
  local attempts=$1; shift
  for i in $(seq 1 "$attempts"); do
    "$@" && return 0
    sleep 3
  done
  return 1
}

token() {
  az account get-access-token \
    --resource https://azuresre.dev \
    --query accessToken -o tsv 2>/dev/null || true
}

rest() {
  az rest --output none "$@"
}

step "1/5" "Load Terraform outputs"

TF_OUT="$(terraform -chdir=infra output -json 2>/dev/null || true)"
if [[ -z "$TF_OUT" ]]; then
  warn "Terraform outputs missing"
  exit 0
fi

read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

AGENT_ID="$(read_tf agent_id)"
AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"

ok "Agent endpoint: $AGENT_ENDPOINT"

# -----------------------------
# Upload knowledge base
# -----------------------------
step "2/5" "Upload knowledge base"

TOKEN="$(token)"
if [[ -z "$TOKEN" ]]; then
  warn "No token — skipping KB upload"
else
  shopt -s nullglob
  for f in knowledge-base/*.md; do
    info "Uploading $(basename "$f")"
    retry 6 curl -sfS -X POST "${AGENT_ENDPOINT}/api/v1/AgentMemory/upload" \
      -H "Authorization: Bearer $TOKEN" \
      -F "triggerIndexing=true" \
      -F "files=@${f};type=text/plain" -o /dev/null
  done
  shopt -u nullglob
  ok "Knowledge base uploaded"
fi

# -----------------------------
# Create subagents
# -----------------------------
step "3/5" "Create subagents"

if [[ -n "$TOKEN" ]]; then
  for yaml in sre-config/agents/*.yaml; do
    body="$(python3 scripts/yaml-to-api-json.py "$yaml")"
    name="$(echo "$body" | jq -r .name)"
    info "Applying $name"
    curl -sf -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/${name}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body" -o /dev/null
  done
  ok "Subagents applied"
else
  warn "No token — skipping"
fi

# -----------------------------
# Enable Azure Monitor
# -----------------------------
step "4/5" "Enable Azure Monitor"

rest --method PATCH \
  --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
  --body '{
    "properties": {
      "incidentManagementConfiguration": {
        "type": "AzMonitor",
        "connectionName": "azmonitor"
      },
      "experimentalSettings": {
        "EnableWorkspaceTools": true,
        "EnableDevOpsTools":    true,
        "EnablePythonTools":    true
      }
    }
  }'

ok "Azure Monitor enabled"
sleep 30

# -----------------------------
# Create response plan
# -----------------------------
step "5/5" "Create response plan"

FILTER_ID="orders-api-http-errors"
FILTER_BODY='{
  "id": "orders-api-http-errors",
  "name": "Orders API HTTP Errors",
  "priorities": ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "handlingAgent": "incident-orchestrator",
  "agentMode": "autonomous",
  "maxAttempts": 3
}'

if [[ -z "$TOKEN" ]]; then
  warn "No token — skipping response plan creation"
  echo
  echo "✅ Data-plane provisioning complete (without response plan)."
  exit 0
fi

retry 5 curl -sf -X PUT \
  "${AGENT_ENDPOINT}/api/v1/incidentPlayground/filters/${FILTER_ID}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data "$FILTER_BODY" -o /dev/null

ok "Response plan created"

echo
echo "✅ Data-plane provisioning complete."
