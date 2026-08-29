#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔥 Simulating Front Door Incident..."
echo ""

# Get resource names from deployment
RG=$(az group list --query "[?contains(name, 's6-frontdoor')].name" -o tsv | head -1)
if [ -z "$RG" ]; then
    echo "❌ No resource group found. Run deploy.sh first."
    exit 1
fi

FD_NAME=$(az resource list -g "$RG" --resource-type "Microsoft.Cdn/profiles" --query "[0].name" -o tsv)
CA_NAME=$(az resource list -g "$RG" --resource-type "Microsoft.App/containerApps" --query "[0].name" -o tsv)

echo "📍 Resource Group: $RG"
echo "🚪 Front Door: $FD_NAME"
echo "📦 Container App: $CA_NAME"
echo ""

# Simulate incident: temporarily scale down container app
echo "⚠️  Scaling down Container App to 0 replicas (simulating unavailability)..."
az containerapp update -n "$CA_NAME" -g "$RG" \
    --min-replicas 0 --max-replicas 1 || {
    echo "❌ Failed to scale container app. Check resource names."
    exit 1
}

echo ""
echo "✅ Incident simulated! The following should happen in 2-5 minutes:"
echo "  1. Azure Monitor alert fires (HTTP 503 spike detected)"
echo "  2. SRE Agent receives webhook alert"
echo "  3. Detector creates incident record"
echo "  4. Triage agent queries logs and identifies root cause"
echo ""
echo "💡 Tip: Watch incident progress with:"
echo "   $SCRIPT_DIR/watch-incident.sh"
echo ""
echo "🔧 To manually resolve:"
echo "   az containerapp update -n $CA_NAME -g $RG --min-replicas 1 --max-replicas 2"
echo ""
