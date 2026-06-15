set -euo pipefail

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"


TF_OUT="$(cd "$ROOT/infra" && terraform output -json 2>/dev/null)"
read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

ORDERS_API_URL="$(read_tf orders_api_url)"
ORDERS_API_NAME="$(read_tf orders_api_name)"
ACR_LOGIN_SERVER="$(read_tf acr_login_server)"
RG="$(echo "$(read_tf agent_id)" | cut -d/ -f5)"

if [[ -z "$ORDERS_API_URL" ]]; then
  echo "❌ Terraform outputs missing. Run 'azd up' first." >&2; exit 1
fi


echo "  Rolling back Container App to orders-api:latest …"
az containerapp update \
  --name           "$ORDERS_API_NAME" \
  --resource-group "$RG" \
  --image          "$ACR_LOGIN_SERVER/orders-api:latest" \
  --output none


echo "  Resetting failure rate …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/reset" -o /dev/null

echo "  Clearing active change request …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/clear-cr" -o /dev/null || true

echo "  Restoring health endpoint …"
curl -sf -X POST "${ORDERS_API_URL}/api/simulate/health/healthy" -o /dev/null || true


echo
echo "✅ orders-api restored to healthy state."
