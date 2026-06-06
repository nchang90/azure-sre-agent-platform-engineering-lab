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

rest() {
  az rest --output none "$@"
}

step "1/7" "Load Terraform outputs"

TF_OUT="$(terraform -chdir=infra output -json 2>/dev/null || true)"
if [[ -z "$TF_OUT" ]]; then
  warn "Terraform outputs missing"
  exit 0
fi

read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

AGENT_ID="$(read_tf agent_id)"
ACR_NAME="$(read_tf acr_name)"
ACR_LOGIN_SERVER="$(read_tf acr_login_server)"
ORDERS_API_NAME="$(read_tf orders_api_name)"
CHANGE_LOOKUP_NAME="$(read_tf change_lookup_name)"
RG="$(echo "$AGENT_ID" | cut -d/ -f5)"

ok "Agent ID: $AGENT_ID"
ok "Resource group: $RG"

# -----------------------------
# Build images
# -----------------------------
step "2/7" "Build container images"

if [[ -n "$ACR_NAME" ]]; then
  az acr build --registry "$ACR_NAME" --image orders-api:latest   src/orders-api/ --no-logs
  az acr build --registry "$ACR_NAME" --image change-lookup:latest change-lookup/ --no-logs
  ok "Images built"
else
  warn "ACR not provisioned — skipping"
fi

# -----------------------------
# Update Container Apps
# -----------------------------
step "3/7" "Update Container Apps"

if [[ -n "$ACR_NAME" ]]; then
  az containerapp update --name "$ORDERS_API_NAME"    --resource-group "$RG" --image "$ACR_LOGIN_SERVER/orders-api:latest" --output none
  az containerapp update --name "$CHANGE_LOOKUP_NAME" --resource-group "$RG" --image "$ACR_LOGIN_SERVER/change-lookup:latest" --output none
  ok "Apps updated"
else
  warn "Skipping — no ACR"
fi

# -----------------------------
# Upload knowledge base
# -----------------------------
step "4/7" "Upload knowledge base"

shopt -s nullglob
for f in knowledge-base/*.md; do
  info "Uploading $(basename "$f")"

  retry 6 az sre agent invoke \
    --agent-id "$AGENT_ID" \
    --method POST \
    --path "/api/v1/AgentMemory/upload?triggerIndexing=true" \
    --file "$f" \
    --output none
done
shopt -u nullglob

ok "Knowledge base uploaded"

# -----------------------------
# Create subagents
# -----------------------------
step "5/7" "Create subagents"

for yaml in sre-config/agents/*.yaml; do
  body="$(python3 scripts/yaml-to-api-json.py "$yaml")"
  name="$(echo "$body" | jq -r .name)"

  info "Applying $name"

  az sre agent invoke \
    --agent-id "$AGENT_ID" \
    --method PUT \
    --path "/api/v2/extendedAgent/agents/${name}" \
    --body "$body" \
    --output none
done

ok "Subagents applied"

# -----------------------------
# Enable Azure Monitor
# -----------------------------
step "6/7" "Enable Azure Monitor"

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
step "7/7" "Create response plan"

FILTER_ID="orders-api-http-errors"
FILTER_BODY='{
  "id": "orders-api-http-errors",
  "name": "Orders API HTTP Errors",
  "priorities": ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "handlingAgent": "incident-orchestrator",
  "agentMode": "autonomous",
  "maxAttempts": 3
}'

retry 5 az sre agent invoke \
  --agent-id "$AGENT_ID" \
  --method PUT \
  --path "/api/v1/incidentPlayground/filters/${FILTER_ID}" \
  --body "$FILTER_BODY" \
  --output none

ok "Response plan created"

echo
echo "✅ Provisioning complete."
