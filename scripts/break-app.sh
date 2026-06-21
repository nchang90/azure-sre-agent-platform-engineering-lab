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
BREAK_MODE="${BREAK_MODE:-both}"
CURRENT_IMAGE=""
RESTORE_IMAGE=""

if [[ -z "$ORDERS_API_NAME" || -z "$ORDERS_API_URL" || -z "$SUB_ID" ]]; then
  echo "❌ Missing Terraform outputs. Run terraform apply for this environment first." >&2
  exit 1
fi

case "$BREAK_MODE" in
  both|5xx|health) ;;
  *)
    echo "❌ Invalid BREAK_MODE '$BREAK_MODE'. Use one of: both, 5xx, health." >&2
    exit 1
    ;;
esac

CURRENT_IMAGE="$(az containerapp show \
  --subscription "$SUB_ID" \
  --name "$ORDERS_API_NAME" \
  --resource-group "$RG" \
  --query 'properties.template.containers[0].image' \
  -o tsv 2>/dev/null || true)"

if [[ -n "$CURRENT_IMAGE" && "$CURRENT_IMAGE" != "$PLACEHOLDER_IMAGE" ]]; then
  RESTORE_IMAGE="$CURRENT_IMAGE"
else
  REVISION_JSON="$(az containerapp revision list \
    --subscription "$SUB_ID" \
    --name "$ORDERS_API_NAME" \
    --resource-group "$RG" \
    -o json 2>/dev/null || echo '[]')"
  RESTORE_IMAGE="$(printf '%s' "$REVISION_JSON" | jq -r --arg placeholder "$PLACEHOLDER_IMAGE" '
    map(select(.properties.template.containers[0].image != $placeholder))
    | sort_by(.properties.createdTime)
    | last
    | .properties.template.containers[0].image // empty
  ' 2>/dev/null || true)"
fi

# The Terraform output uses latest_revision_fqdn, which pins to a specific
# revision and goes stale after an image update (calls then 404 on an old
# revision). Prefer the stable ingress FQDN, which always routes to the
# active revision; fall back to the Terraform URL if the lookup fails.
STABLE_FQDN="$(az containerapp show \
  --subscription "$SUB_ID" \
  --name "$ORDERS_API_NAME" \
  --resource-group "$RG" \
  --query 'properties.configuration.ingress.fqdn' \
  -o tsv 2>/dev/null || true)"
if [[ -n "$STABLE_FQDN" ]]; then
  ORDERS_API_URL="https://$STABLE_FQDN"
fi

CHANGE_ID="CHG$(date +%s)"

runtime_5xx_applied=false
health_applied=false
used_image_fallback=false

trigger_runtime_5xx() {
  echo "  Announcing active change ID ($CHANGE_ID) and enabling runtime 5xx simulation …"
  curl -fsS -X POST "$ORDERS_API_URL/api/simulate/active-cr/$CHANGE_ID" >/dev/null || return 1
  curl -fsS -X POST "$ORDERS_API_URL/api/simulate/failure-rate/100" >/dev/null || return 1

  echo "  Sending failing order traffic to populate AppRequests …"
  for i in $(seq 1 25); do
    curl -fsS -X POST "$ORDERS_API_URL/api/orders" \
      -H "Content-Type: application/json" \
      -d '{"customerId":"chaos-'"$i"'","sku":"SKU-001","quantity":1}' >/dev/null || true
  done

  echo "  Calling fixed 500 endpoint …"
  for i in $(seq 1 5); do
    curl -fsS "$ORDERS_API_URL/api/orders/fail" >/dev/null || true
  done

  runtime_5xx_applied=true
}

trigger_runtime_health_break() {
  echo "  Enabling runtime unhealthy health probe mode …"
  curl -fsS -X POST "$ORDERS_API_URL/api/simulate/health/unhealthy" >/dev/null || return 1
  health_applied=true
}

trigger_image_health_break() {
  echo "  Runtime health endpoint unavailable; switching to image fallback …"
  echo "  Updating Container App to placeholder image that fails the /health probe …"
  az containerapp update \
    --subscription "$SUB_ID" \
    --name "$ORDERS_API_NAME" \
    --resource-group "$RG" \
    --image "$PLACEHOLDER_IMAGE" \
    --output none
  health_applied=true
  used_image_fallback=true
}

case "$BREAK_MODE" in
  both)
    echo "  Break mode: both (5xx + health)"
    if ! trigger_runtime_5xx; then
      echo "❌ Runtime 5xx simulation endpoints are unavailable on the current revision." >&2
      echo "   Health break will still be applied, but the 5xx incident path is not guaranteed until the app is refreshed to a revision that exposes /api/simulate/*." >&2
    fi
    trigger_runtime_health_break || trigger_image_health_break
    ;;
  5xx)
    echo "  Break mode: 5xx"
    if ! trigger_runtime_5xx; then
      echo "❌ Runtime 5xx simulation endpoints are unavailable on the current revision." >&2
      echo "   Refresh the app revision, then retry with BREAK_MODE=5xx." >&2
      exit 1
    fi
    ;;
  health)
    echo "  Break mode: health"
    trigger_runtime_health_break || trigger_image_health_break
    ;;
esac

echo
if [[ "$BREAK_MODE" == "both" && "$runtime_5xx_applied" != true ]]; then
  echo "⚠️  Partial break applied."
else
  echo "✅ Break action applied."
fi
if [[ "$runtime_5xx_applied" == true ]]; then
  echo "   5xx responses have been generated and the orders-api-errors alert should evaluate within minutes."
fi
if [[ "$health_applied" == true ]]; then
  echo "   Health probe failures have been applied and the orders-api-health alert should evaluate within seconds to minutes."
fi
echo "   Watch the agent triage at: $(printf '%s' "$TF_OUT" | jq -r '.agent_portal_url.value // empty')"
echo "   To restore runtime mode:  POST $ORDERS_API_URL/api/simulate/reset && POST $ORDERS_API_URL/api/simulate/clear-cr && POST $ORDERS_API_URL/api/simulate/health/healthy"
if [[ -n "$RESTORE_IMAGE" ]]; then
  echo "   To restore image mode:    az containerapp update -g $RG -n $ORDERS_API_NAME --image $RESTORE_IMAGE"
else
  echo "   To restore image mode:    az containerapp update -g $RG -n $ORDERS_API_NAME --image <working-image>"
fi

if [[ "$BREAK_MODE" == "both" && "$runtime_5xx_applied" != true ]]; then
  exit 2
fi
