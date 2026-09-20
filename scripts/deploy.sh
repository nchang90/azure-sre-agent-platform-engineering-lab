#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO]  $*"; }
ok()  { echo "[OK]    $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

ENVIRONMENT="${1:?Usage: bash scripts/deploy.sh ENVIRONMENT [PLAN_FILE]}"
PLAN_FILE="${2:-tfplan}"
TF_OUT=""

read_tf() { jq -r ".${1}.value // empty" <<<"$TF_OUT"; }

terraform_apply() {
  local output exit_code

  set +e
  output="$(terraform -chdir=infra/terraform apply -auto-approve "$PLAN_FILE" 2>&1)"
  exit_code=$?
  set -e
  echo "$output"

  [[ $exit_code -eq 0 ]] && return 0

  if grep -qi "workspace could not be found" <<<"$output"; then
    log "Terraform apply hit a transient workspace lookup issue; retrying once..."
    sleep 10
    terraform -chdir=infra/terraform apply -auto-approve "$PLAN_FILE"
  else
    return "$exit_code"
  fi
}

dump_aks_diagnostics() {
  kubectl get pods --namespace default -l app=checkout-api -o wide
  kubectl describe deployment/checkout-api --namespace default
  kubectl describe pods --namespace default -l app=checkout-api
}

deploy_aks_workload() {
  local aks_name agent_id resource_group
  aks_name="$(read_tf aks_name)"

  if [[ -z "$aks_name" ]]; then
    log "AKS stack is disabled; skipping AKS workload deployment."
    return 0
  fi

  agent_id="$(read_tf agent_id)"
  resource_group="$(cut -d/ -f5 <<<"$agent_id")"

  az aks get-credentials \
    --resource-group "$resource_group" \
    --name "$aks_name" \
    --admin \
    --overwrite-existing

  kubectl apply -f infra/k8s/checkout-api.yaml
  if ! kubectl rollout status deployment/checkout-api --namespace default --timeout=180s; then
    dump_aks_diagnostics
    die "The deployment failed; investigate the AKS alert through Azure SRE Agent."
  fi
  ok "checkout-api rolled out to $aks_name."
}

build_and_update_images() {
  local acr_name login_server orders_api change_lookup runtime_stack agent_id resource_group
  acr_name="$(read_tf acr_name)"

  if [[ -z "$acr_name" ]]; then
    log "Container Apps stack is disabled; skipping image build and app updates."
    return 0
  fi

  login_server="$(read_tf acr_login_server)"
  orders_api="$(read_tf orders_api_name)"
  change_lookup="$(read_tf change_lookup_name)"
  runtime_stack="$(read_tf runtime_stack)"
  agent_id="$(read_tf agent_id)"
  resource_group="$(cut -d/ -f5 <<<"$agent_id")"

  log "Building images in ACR: $acr_name"
  az acr build --registry "$acr_name" --image orders-api:latest src/orders-api/
  az acr build --registry "$acr_name" --image change-lookup:latest src/change-lookup/

  case "$runtime_stack" in
    containerapps)
      az containerapp update --name "$orders_api" --resource-group "$resource_group" \
        --image "$login_server/orders-api:latest" --output none
      az containerapp update --name "$change_lookup" --resource-group "$resource_group" \
        --image "$login_server/change-lookup:latest" --output none
      ok "Container Apps updated."
      ;;
    webapp)
      az webapp restart --resource-group "$resource_group" --name "$orders_api"
      az webapp restart --resource-group "$resource_group" --name "$change_lookup"
      ok "App Service apps restarted."
      ;;
    *)
      log "No image-based runtime update is required for $runtime_stack."
      ;;
  esac
}

log "Applying Terraform plan for $ENVIRONMENT..."
terraform_apply
TF_OUT="$(terraform -chdir=infra/terraform output -json)"
RUNTIME_STACK_OVERRIDE="$(read_tf runtime_stack)" bash "$SCRIPT_DIR/apply-extras.sh" "$ENVIRONMENT"
deploy_aks_workload
build_and_update_images
ok "Deployment completed for $ENVIRONMENT."
