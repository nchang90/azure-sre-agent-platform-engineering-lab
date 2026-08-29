#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "👁️  Watching Incident Response..."
echo ""

# Get resource group
RG=$(az group list --query "[?contains(name, 's6-frontdoor')].name" -o tsv | head -1)
if [ -z "$RG" ]; then
    echo "❌ No resource group found."
    exit 1
fi

echo "📊 Monitoring Azure Monitor alerts in resource group: $RG"
echo ""

# Watch alerts
while true; do
    ALERTS=$(az monitor metrics list \
        --resource-group "$RG" \
        --resource-type "Microsoft.App/containerApps" \
        --metric "HttpRequestsTotal" \
        --start-time "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S)Z" \
        --interval PT1M \
        --aggregation Total 2>/dev/null || echo "")
    
    if [ -n "$ALERTS" ]; then
        echo "✅ Activity detected:"
        echo "$ALERTS" | jq '.' 2>/dev/null || echo "$ALERTS"
    else
        echo "⏳ Waiting for alerts..."
    fi
    
    sleep 10
done
