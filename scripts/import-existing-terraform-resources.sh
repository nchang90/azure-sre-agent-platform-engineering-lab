#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform"

ENVIRONMENT="${1:?Usage: bash scripts/import-existing-terraform-resources.sh ENVIRONMENT RUNTIME}"
RUNTIME="${2:?Usage: bash scripts/import-existing-terraform-resources.sh ENVIRONMENT RUNTIME}"
VARS_FILE="environments/${ENVIRONMENT}.tfvars"

metadata="$(
  terraform -chdir="$TF_DIR" console \
    -var-file="$VARS_FILE" \
    -var="runtime=$RUNTIME" <<'EOF'
jsonencode({
  suffix          = local.suffix
  resource_group  = var.resource_group_name
  agent_name      = var.agent_name
  create_identity = local.create_identity
  images_enabled  = local.images_enabled
  webapps_enabled = local.webapps_enabled
})
EOF
)"

suffix="$(jq -r '.suffix' <<<"$metadata")"
resource_group="$(jq -r '.resource_group' <<<"$metadata")"
agent_name="$(jq -r '.agent_name' <<<"$metadata")"
subscription_id="$(az account show --query id --output tsv)"

import_if_missing_from_state() {
  local address="$1"
  local resource_id="$2"

  if terraform -chdir="$TF_DIR" state show "$address" >/dev/null 2>&1; then
    return
  fi

  if ! az resource show --ids "$resource_id" --query id --output tsv >/dev/null 2>&1; then
    return
  fi

  echo "[INFO] Importing existing Azure resource into Terraform state: $address"
  terraform -chdir="$TF_DIR" import \
    -var-file="$VARS_FILE" \
    -var="runtime=$RUNTIME" \
    "$address" "$resource_id"
}

if [[ "$(jq -r '.create_identity' <<<"$metadata")" == "true" ]]; then
  import_if_missing_from_state \
    'azurerm_user_assigned_identity.agent[0]' \
    "/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${agent_name}-id-${suffix}"
fi

if [[ "$(jq -r '.images_enabled' <<<"$metadata")" == "true" ]]; then
  import_if_missing_from_state \
    'azurerm_user_assigned_identity.apps[0]' \
    "/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-apps-${suffix}"
fi

if [[ "$(jq -r '.webapps_enabled' <<<"$metadata")" == "true" ]]; then
  import_if_missing_from_state \
    'azurerm_service_plan.webapps[0]' \
    "/subscriptions/$subscription_id/resourceGroups/$resource_group/providers/Microsoft.Web/serverFarms/asp-${suffix}"
fi
