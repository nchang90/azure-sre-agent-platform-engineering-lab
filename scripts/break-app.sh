#!/usr/bin/env bash
set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"

BACKEND_ENV="${TF_BACKEND_ENV:-${AZD_ENV_NAME:-${ENVIRONMENT:-}}}"

if [[ -z "$BACKEND_ENV" && -f "$ROOT/infra/.terraform/terraform.tfstate" ]]; then
  BACKEND_KEY="$(jq -r '.backend.config.key // empty' "$ROOT/infra/.terraform/terraform.tfstate" 2>/dev/null || true)"
  BACKEND_ENV="${BACKEND_KEY%%_*}"
fi

if [[ -z "$BACKEND_ENV" ]]; then
  if [[ -f "$ROOT/infra/backend/sbox.backend.tfvars" ]]; then
    BACKEND_ENV="sbox"
  elif [[ -f "$ROOT/infra/backend/demo.backend.tfvars" ]]; then
    BACKEND_ENV="demo"
  fi
fi

BACKEND_FILE="$ROOT/infra/backend/${BACKEND_ENV}.backend.tfvars"

if [[ -f "$BACKEND_FILE" ]]; then
  echo "  Initializing Terraform backend (${BACKEND_ENV}) …"
  (cd "$ROOT/infra" && terraform init -reconfigure -backend-config="$BACKEND_FILE" -input=false -no-color >/dev/null)
fi

TF_OUT="$(cd "$ROOT/infra" && terraform output -json 2>/dev/null || true)"

ACR_NAME="$(printf '%s' "$TF_OUT" | jq -r '.acr_name.value // empty')"
ACR_LOGIN_SERVER="$(printf '%s' "$TF_OUT" | jq -r '.acr_login_server.value // empty')"
ORDERS_API_NAME="$(printf '%s' "$TF_OUT" | jq -r '.orders_api_name.value // empty')"
AGENT_ID="$(printf '%s' "$TF_OUT" | jq -r '.agent_id.value // empty')"
RG="$(echo "$AGENT_ID" | cut -d/ -f5)"
SUB_ID="$(echo "$AGENT_ID" | cut -d/ -f3)"

if [[ -z "$ACR_NAME" || -z "$ACR_LOGIN_SERVER" || -z "$ORDERS_API_NAME" || -z "$SUB_ID" ]]; then
  echo "❌ Missing Terraform outputs. Run terraform apply for this environment first." >&2
  exit 1
fi

ROGUE_TAG="rogue-$(date +%s)"

echo "  Building rogue image ($ROGUE_TAG) …"
az acr build \
  --subscription "$SUB_ID" \
  --registry "$ACR_NAME" \
  --image "orders-api:${ROGUE_TAG}" \
  "$ROOT/src/orders-api/" \
  --no-logs

echo "  Updating Container App to rogue image …"
az containerapp update \
  --subscription "$SUB_ID" \
  --name "$ORDERS_API_NAME" \
  --resource-group "$RG" \
  --image "$ACR_LOGIN_SERVER/orders-api:${ROGUE_TAG}" \
  --output none

echo
echo "✅ Container App updated to rogue revision."
echo "   Watch the agent triage at: $(printf '%s' "$TF_OUT" | jq -r '.agent_portal_url.value // empty')"
echo "   To restore:  bash scripts/reset-app.sh"
