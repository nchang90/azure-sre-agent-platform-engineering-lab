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

ORDERS_API_NAME="$(printf '%s' "$TF_OUT" | jq -r '.orders_api_name.value // empty')"
ORDERS_API_URL="$(printf '%s' "$TF_OUT" | jq -r '.orders_api_url.value // empty')"
AGENT_ID="$(printf '%s' "$TF_OUT" | jq -r '.agent_id.value // empty')"
RG="$(echo "$AGENT_ID" | cut -d/ -f5)"
SUB_ID="$(echo "$AGENT_ID" | cut -d/ -f3)"
PLACEHOLDER_IMAGE="mcr.microsoft.com/k8se/quickstart:latest"

if [[ -z "$ORDERS_API_NAME" || -z "$ORDERS_API_URL" || -z "$SUB_ID" ]]; then
  echo "❌ Missing Terraform outputs. Run terraform apply for this environment first." >&2
  exit 1
fi

CHANGE_ID="CHG$(date +%s)"

echo "  Attempting runtime 5xx simulation ($CHANGE_ID) …"
if curl -fsS -X POST "$ORDERS_API_URL/api/simulate/active-cr/$CHANGE_ID" >/dev/null \
  && curl -fsS -X POST "$ORDERS_API_URL/api/simulate/failure-rate/100" >/dev/null; then
  echo "  Sending traffic to generate 5xx responses …"
  for i in $(seq 1 25); do
    curl -fsS -X POST "$ORDERS_API_URL/api/orders" \
      -H "Content-Type: application/json" \
      -d '{"customerId":"chaos-'"$i"'","sku":"SKU-001","quantity":1}' >/dev/null || true
  done
  echo "  Triggering fixed 5xx endpoint …"
  for i in $(seq 1 5); do
    curl -fsS "$ORDERS_API_URL/api/orders/fail" >/dev/null || true
  done
else
  echo "  Runtime simulation endpoint unavailable; switching to fallback break mode …"
  echo "  Updating Container App to placeholder image that fails the /health probe …"
  az containerapp update \
    --subscription "$SUB_ID" \
    --name "$ORDERS_API_NAME" \
    --resource-group "$RG" \
    --image "$PLACEHOLDER_IMAGE" \
    --output none
fi

echo
echo "✅ Break action applied."
echo "   If runtime simulation succeeded, 5xx responses have been generated and the 5xx alert should evaluate within minutes."
echo "   If fallback image mode was used, the Container App liveness probe should start failing within seconds."
echo "   Watch the agent triage at: $(printf '%s' "$TF_OUT" | jq -r '.agent_portal_url.value // empty')"
echo "   To restore runtime mode:  POST $ORDERS_API_URL/api/simulate/reset && POST $ORDERS_API_URL/api/simulate/clear-cr"
echo "   To restore image mode:    az containerapp update -g $RG -n $ORDERS_API_NAME --image <working-image>"
