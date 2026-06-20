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

ORDERS_API_URL="$(printf '%s' "$TF_OUT" | jq -r '.orders_api_url.value // empty')"

if [[ -z "$ORDERS_API_URL" ]]; then
  echo "❌ Missing Terraform outputs. Run terraform apply for this environment first." >&2
  exit 1
fi

echo "  Clearing active change request …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/clear-cr" -o /dev/null || true

echo "  Setting failure rate to 100% …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/failure-rate/100" -o /dev/null

echo "  Setting health to unhealthy …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/health/unhealthy" -o /dev/null

echo "  Generating 5xx traffic (60 requests) …"
for i in $(seq 1 60); do
  # /api/orders/fail is an intentional always-500 endpoint for alert demos.
  curl -s "${ORDERS_API_URL}/api/orders/fail" -o /dev/null || true
done

echo
echo "✅ App broken. Azure Monitor alert should fire in ~2 minutes."
echo "   Watch the agent triage at: $(printf '%s' "$TF_OUT" | jq -r '.agent_portal_url.value // empty')"
echo "   To restore:  bash scripts/reset-app.sh"
