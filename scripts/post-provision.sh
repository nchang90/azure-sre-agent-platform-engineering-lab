#!/usr/bin/env bash
set -euo pipefail

log()  { echo -e "\033[1;34m[INFO]\033[0m $1"; }
ok()   { echo -e "\033[1;32m[ OK ]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERR ]\033[0m $1"; }

# ---------------------------------------------------------
# 1/7 — Load Terraform outputs
# ---------------------------------------------------------
log "Loading Terraform outputs..."

TF_OUT="$(terraform -chdir=infra output -json 2>/dev/null || true)"
if [[ -z "$TF_OUT" ]]; then
  err "Terraform outputs missing"
  exit 1
fi

read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

AGENT_ID="$(read_tf agent_id)"
AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"   # <-- FIXED
ACR_NAME="$(read_tf acr_name)"
ACR_LOGIN_SERVER="$(read_tf acr_login_server)"
ORDERS_API_NAME="$(read_tf orders_api_name)"
CHANGE_LOOKUP_NAME="$(read_tf change_lookup_name)"
RG="$(echo "$AGENT_ID" | cut -d/ -f5)"

ok "Agent ID: $AGENT_ID"
ok "Resource group: $RG"
ok "Agent endpoint: $AGENT_ENDPOINT"

if [[ -z "$AGENT_ENDPOINT" ]]; then
  err "agent_data_plane_url output missing — cannot continue"
  exit 1
fi

# Extract hostname (strip https://)
HOSTNAME="$(echo "$AGENT_ENDPOINT" | sed 's~https\?://~~')"
log "Resolved hostname: $HOSTNAME"

# ---------------------------------------------------------
# 2/7 — Wait for DNS propagation
# ---------------------------------------------------------
log "Waiting for DNS to resolve..."

for i in {1..30}; do
  if nslookup "$HOSTNAME" >/dev/null 2>&1; then
    ok "DNS resolved for $HOSTNAME"
    break
  fi
  warn "DNS not ready yet... retrying ($i/30)"
  sleep 10
done

if ! nslookup "$HOSTNAME" >/dev/null 2>&1; then
  err "DNS did not propagate in time"
  exit 1
fi

# ---------------------------------------------------------
# 3/7 — Wait for SRE Agent health
# ---------------------------------------------------------
log "Checking SRE Agent health..."

for i in {1..30}; do
  if curl -s --max-time 5 "$AGENT_ENDPOINT/health" | grep -q "healthy"; then
    ok "SRE Agent is healthy"
    break
  fi
  warn "Agent not healthy yet... retrying ($i/30)"
  sleep 10
done

if ! curl -s "$AGENT_ENDPOINT/health" | grep -q "healthy"; then
  err "SRE Agent did not become healthy"
  exit 1
fi

# ---------------------------------------------------------
# 4/7 — Load knowledge base
# ---------------------------------------------------------
log "Loading knowledge base..."
curl -s -X POST "$AGENT_ENDPOINT/knowledge/load" \
  -H "Content-Type: application/json" \
  -d @knowledge.json
ok "Knowledge loaded"

# ---------------------------------------------------------
# 5/7 — Register subagents
# ---------------------------------------------------------
log "Registering subagents..."
curl -s -X POST "$AGENT_ENDPOINT/subagents/register" \
  -H "Content-Type: application/json" \
  -d @subagents.json
ok "Subagents registered"

# ---------------------------------------------------------
# 6/7 — Upload response plan
# ---------------------------------------------------------
log "Uploading response plan..."
curl -s -X POST "$AGENT_ENDPOINT/response-plan" \
  -H "Content-Type: application/json" \
  -d @response-plan.json
ok "Response plan uploaded"

# ---------------------------------------------------------
# 7/7 — Done
# ---------------------------------------------------------
ok "Post-provision setup completed successfully"
