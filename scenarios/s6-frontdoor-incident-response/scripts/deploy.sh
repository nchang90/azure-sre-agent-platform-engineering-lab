#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🚀 Deploying S6: Front Door Incident Response Infrastructure..."

# Set Azure environment
ENVIRONMENT="s6-frontdoor"
RESOURCE_GROUP="s6-frontdoor-${USER}"

echo "📦 Resource Group: $RESOURCE_GROUP"
echo "🌍 Environment: $ENVIRONMENT"

# Deploy using azd
cd "$REPO_ROOT"
export AZURE_ENV_NAME="$ENVIRONMENT"

echo "🔧 Running infrastructure deployment..."
azd up --no-prompt || {
    echo "❌ azd up failed. Check subscription and permissions."
    exit 1
}

echo ""
echo "✅ Infrastructure deployed successfully!"
echo ""
echo "📊 Next steps:"
echo "  1. View Application Insights alerts:"
echo "     az monitor metrics list --resource $RESOURCE_GROUP --interval PT1M"
echo ""
echo "  2. Simulate incident:"
echo "     $SCRIPT_DIR/simulate-incident.sh"
echo ""
echo "  3. Watch SRE agent response:"
echo "     $SCRIPT_DIR/watch-incident.sh"
echo ""
