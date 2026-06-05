#!/usr/bin/env bash
# scripts/break-app.sh — Scenario 2: simulate an unauthorized deploy + 5xx surge.
#
# What this does:
#   1. Builds a "rogue" image (missing auth header) via ACR Tasks
#   2. Deploys it directly to the orders-api Container App (bypassing a CR)
#   3. Clears the active change request so /health shows no linked CR
#   4. Drives 100% failure rate to generate Azure Monitor alerts
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"

echo "🚨 Breaking orders-api (Scenario 2 — unauthorized deploy)"

TF_OUT="$(cd "$ROOT/infra" && terraform output -json 2>/dev/null)"
read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

ACR_NAME="$(read_tf acr_name)"
ACR_LOGIN_SERVER="$(read_tf acr_login_server)"
ORDERS_API_NAME="$(read_tf orders_api_name)"
ORDERS_API_URL="$(read_tf orders_api_url)"
RG="$(echo "$(read_tf agent_id)" | cut -d/ -f5)"

if [[ -z "$ACR_NAME" || -z "$ORDERS_API_NAME" ]]; then
  echo "❌ Terraform outputs missing. Run 'azd up' first." >&2; exit 1
fi

ROGUE_TAG="rogue-$(date +%s)"

echo "  Building rogue image ($ROGUE_TAG) …"
az acr build \
  --registry "$ACR_NAME" \
  --image    "orders-api:${ROGUE_TAG}" \
  "$ROOT/src/orders-api/" \
  --no-logs

echo "  Deploying rogue image (no change request) …"
az containerapp update \
  --name           "$ORDERS_API_NAME" \
  --resource-group "$RG" \
  --image          "$ACR_LOGIN_SERVER/orders-api:${ROGUE_TAG}" \
  --output none

echo "  Clearing active change request …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/clear-cr" -o /dev/null || true

echo "  Setting failure rate to 100% …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/failure-rate/100" -o /dev/null

echo "  Generating 5xx traffic (60 requests) …"
for i in $(seq 1 60); do
  curl -sf "${ORDERS_API_URL}/api/orders" -o /dev/null || true
done

echo
echo "✅ App broken. Azure Monitor alert should fire in ~2 minutes."
echo "   Watch the agent triage at: $(read_tf agent_portal_url)"
echo "   To restore:  bash scripts/reset-app.sh"
