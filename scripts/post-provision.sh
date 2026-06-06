#!/usr/bin/env bash
set -euo pipefail

RETRY=false
[[ "${1:-}" == "--retry" ]] && RETRY=true

D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$D/.." && pwd)"

# ── helpers ───────────────────────────────────────────────────────────────────

step() { echo; echo "▶ Step $1/8 — $2"; }
info() { echo "  $*"; }
ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }

get_token() {
  az account get-access-token \
    --resource https://azuresre.dev \
    --query accessToken -o tsv 2>/dev/null || true
}

# ── Step 1 — Sync TF outputs into local vars ──────────────────────────────────

step 1 "Sync Terraform outputs"
AZD_ENV_NAME="${AZURE_ENV_NAME:-}"
if [[ -z "$AZD_ENV_NAME" ]] && command -v azd >/dev/null 2>&1; then
  AZD_ENV_NAME="$(azd env get-values 2>/dev/null | awk -F= '$1 == "AZURE_ENV_NAME" { gsub(/\"/, "", $2); print $2; exit }' || true)"
fi

AZD_TF_STATE=""
if [[ -n "$AZD_ENV_NAME" ]]; then
  AZD_TF_STATE="$ROOT/.azure/$AZD_ENV_NAME/infra/terraform.tfstate"
fi

if [[ -n "$AZD_TF_STATE" && -s "$AZD_TF_STATE" ]]; then
  TF_OUT="$(terraform -chdir="$ROOT/infra" output -state="$AZD_TF_STATE" -json 2>/dev/null || true)"
else
  TF_OUT="$(terraform -chdir="$ROOT/infra" output -json 2>/dev/null || true)"
fi

strict_fail="${POST_PROVISION_STRICT:-false}"

if [[ -z "$TF_OUT" ]] || ! echo "$TF_OUT" | jq -e . >/dev/null 2>&1; then
  warn "Terraform outputs are not available yet."
  warn "Provision likely failed earlier. Fix infra errors, then re-run: azd up"
  if [[ "$strict_fail" == "true" ]]; then
    echo "❌ Could not read Terraform outputs." >&2
    exit 1
  fi
  exit 0
fi

read_tf() { echo "$TF_OUT" | jq -r ".${1}.value // empty"; }

AGENT_ID="$(read_tf agent_id)"
AGENT_ENDPOINT="$(read_tf agent_data_plane_url)"
ACR_NAME="$(read_tf acr_name)"
ACR_LOGIN_SERVER="$(read_tf acr_login_server)"
ORDERS_API_NAME="$(read_tf orders_api_name)"
CHANGE_LOOKUP_NAME="$(read_tf change_lookup_name)"

# Derive resource group from agent resource ID
RG="$(echo "$AGENT_ID" | cut -d/ -f5)"

if [[ -z "$AGENT_ID" || -z "$AGENT_ENDPOINT" ]]; then
  warn "Missing required Terraform outputs (agent_id or agent_data_plane_url)."
  warn "Provision likely failed earlier. Fix infra errors, then re-run: azd up"
  if [[ "$strict_fail" == "true" ]]; then
    echo "❌ Could not read required Terraform outputs." >&2
    exit 1
  fi
  exit 0
fi

# Sync into azd env if running under azd
if command -v azd >/dev/null 2>&1; then
  azd env set AGENT_ID           "$AGENT_ID"           2>/dev/null || true
  azd env set AGENT_ENDPOINT     "$AGENT_ENDPOINT"     2>/dev/null || true
  azd env set ORDERS_API_NAME    "$ORDERS_API_NAME"    2>/dev/null || true
  azd env set CHANGE_LOOKUP_NAME "$CHANGE_LOOKUP_NAME" 2>/dev/null || true
fi

ok "Agent endpoint: $AGENT_ENDPOINT"
ok "Resource group: $RG"

# ── Step 2 — Build container images via ACR Tasks ─────────────────────────────

step 2 "Build container images"
if $RETRY; then
  info "Skipped (--retry)"
else
  if [[ -z "$ACR_NAME" ]]; then
    warn "ACR not provisioned (deploy_apps = false) — skipping image builds"
  else
    info "Building orders-api …"
    az acr build \
      --registry "$ACR_NAME" \
      --image    orders-api:latest \
      "$ROOT/src/orders-api/" --no-logs

    info "Building change-lookup …"
    az acr build \
      --registry "$ACR_NAME" \
      --image    change-lookup:latest \
      "$ROOT/change-lookup/" --no-logs

    ok "Images pushed to $ACR_LOGIN_SERVER"
  fi
fi

# ── Step 3 — Update Container Apps to new images ──────────────────────────────

step 3 "Update Container Apps"
if $RETRY; then
  info "Skipped (--retry)"
else
  if [[ -z "$ACR_NAME" ]]; then
    warn "ACR not provisioned — skipping Container App update"
  else
    az containerapp update \
      --name           "$ORDERS_API_NAME" \
      --resource-group "$RG" \
      --image          "$ACR_LOGIN_SERVER/orders-api:latest" \
      --output none

    az containerapp update \
      --name           "$CHANGE_LOOKUP_NAME" \
      --resource-group "$RG" \
      --image          "$ACR_LOGIN_SERVER/change-lookup:latest" \
      --output none

    ok "Container Apps updated"
  fi
fi

# ── Step 4 — Upload knowledge base ────────────────────────────────────────────

step 4 "Upload knowledge base"
TOKEN="$(get_token)"
if [[ -z "$TOKEN" ]]; then
  warn "No SRE Agent token — run: az login && az account set -s <sub>"
  warn "Then re-run: bash scripts/post-provision.sh --retry"
else
  for f in "$ROOT/knowledge-base/"*.md; do
    name="$(basename "$f")"
    info "Uploading $name …"
    curl -sfS --retry 6 --retry-delay 3 --retry-all-errors -X POST "${AGENT_ENDPOINT}/api/v1/AgentMemory/upload" \
      -H "Authorization: Bearer $TOKEN" \
      -F "triggerIndexing=true" \
      -F "files=@${f};type=text/plain" \
      -o /dev/null
  done
  ok "Knowledge base uploaded"
fi

# ── Step 5 — Create / update subagents ────────────────────────────────────────

step 5 "Create subagents"
if [[ -z "$TOKEN" ]]; then
  warn "Skipped (no token)"
else
  for yaml_file in \
    "$ROOT/sre-config/agents/orchestrator-agent.yaml" \
    "$ROOT/sre-config/agents/triage-agent.yaml"; do

    name="$(python3 "$ROOT/scripts/yaml-to-api-json.py" "$yaml_file" | jq -r .name)"
    info "Applying $name …"
    body="$(python3 "$ROOT/scripts/yaml-to-api-json.py" "$yaml_file")"

    curl -sf -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/${name}" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body" \
      -o /dev/null

    ok "  $name"
  done
fi

# ── Step 6 — Enable Azure Monitor as incident platform ────────────────────────

step 6 "Enable Azure Monitor"
az rest \
  --method PATCH \
  --url "https://management.azure.com${AGENT_ID}?api-version=2025-05-01-preview" \
  --body '{
    "properties": {
      "incidentManagementConfiguration": {
        "type": "AzMonitor",
        "connectionName": "azmonitor"
      },
      "experimentalSettings": {
        "EnableWorkspaceTools": true,
        "EnableDevOpsTools":    true,
        "EnablePythonTools":    true
      }
    }
  }' \
  --output none

ok "Azure Monitor enabled — waiting 30s for it to initialize …"
sleep 30

# ── Step 7 — Create response plan (retry up to 5×) ────────────────────────────

step 7 "Create response plan"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(get_token)"
fi

FILTER_ID="orders-api-http-errors"
FILTER_BODY='{
  "id":             "orders-api-http-errors",
  "name":           "Orders API HTTP Errors",
  "priorities":     ["Sev0","Sev1","Sev2","Sev3","Sev4"],
  "titleContains":  "",
  "handlingAgent":  "incident-orchestrator",
  "agentMode":      "autonomous",
  "maxAttempts":    3
}'

for attempt in 1 2 3 4 5; do
  rc=0
  curl -sf -X PUT "${AGENT_ENDPOINT}/api/v1/incidentPlayground/filters/${FILTER_ID}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "$FILTER_BODY" \
    -o /dev/null || rc=$?

  if [[ $rc -eq 0 ]]; then
    ok "Response plan created"
    break
  fi

  if [[ $attempt -lt 5 ]]; then
    info "Attempt $attempt failed — retrying in 15s …"
    sleep 15
    TOKEN="$(get_token)"
  else
    warn "Could not create response plan after 5 attempts. Retry manually:"
    warn "  bash scripts/post-provision.sh --retry"
  fi
done

# ── Step 8 — Create scheduled task (GitHub issue triage) ──────────────────────

step 8 "Create scheduled task"
GITHUB_REPO="${GITHUB_REPO:-}"

if [[ -z "$TOKEN" ]]; then
  TOKEN="$(get_token)"
fi

if [[ -n "$GITHUB_REPO" ]]; then
  # Register GitHub connector (data-plane)
  info "Registering GitHub connector …"
  curl -sf -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/connectors/github" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data '{
      "name":  "github",
      "type":  "AgentConnector",
      "properties": {
        "dataConnectorType": "GitHubOAuth",
        "dataSource":        "github-oauth"
      }
    }' \
    -o /dev/null

  # Register code repo
  REPO_NAME="${GITHUB_REPO//\//-}"
  info "Registering repo $GITHUB_REPO …"
  curl -sf -X PUT "${AGENT_ENDPOINT}/api/v2/repos/${REPO_NAME}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
      \"name\": \"${REPO_NAME}\",
      \"type\": \"CodeRepo\",
      \"properties\": {
        \"url\":               \"https://github.com/${GITHUB_REPO}\",
        \"authConnectorName\": \"github\"
      }
    }" \
    -o /dev/null

  # Create issue-triager subagent
  if [[ -f "$ROOT/sre-config/agents/issue-triager.yaml" ]]; then
    info "Applying issue-triager …"
    body="$(python3 "$ROOT/scripts/yaml-to-api-json.py" "$ROOT/sre-config/agents/issue-triager.yaml")"
    curl -sf -X PUT "${AGENT_ENDPOINT}/api/v2/extendedAgent/agents/issue-triager" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "$body" \
      -o /dev/null
    ok "issue-triager subagent created"
  fi

  # Create scheduled task every 12 hours
  info "Creating scheduled task triage-orders-issues …"
  curl -sf -X POST "${AGENT_ENDPOINT}/api/v1/scheduledtasks" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data "{
      \"name\":           \"triage-orders-issues\",
      \"description\":    \"Triage open [Customer Issue] GitHub issues every 12 hours\",
      \"cronExpression\": \"0 */12 * * *\",
      \"agentPrompt\":    \"Fetch open issues in ${GITHUB_REPO} labelled or titled with [Customer Issue]. For each untriaged issue: extract any CR number, look it up in the change-lookup service, classify the issue (Bug / Change-Related-Incident / Policy-Violation / Question / Feature-Request), add appropriate labels, and post a structured triage comment beginning with \\\"🤖 **SRE Agent**\\\". Skip issues that already have an SRE Agent comment.\",
      \"agent\":          \"issue-triager\"
    }" \
    -o /dev/null
  ok "Scheduled task created (runs every 12 h)"
else
  info "GITHUB_REPO not set — skipping GitHub integration"
  info "Set GITHUB_REPO=owner/repo and re-run to enable scenario 4 (issue triage)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo
echo "✅ Provisioning complete."
echo "   Agent portal: $(read_tf agent_portal_url)"
echo
echo "   Next steps:"
echo "   • Scenario 2 (unauthorized deploy):  bash scripts/break-app.sh"
echo "   • Scenario 4 (GitHub triage):        GITHUB_REPO=owner/repo bash scripts/post-provision.sh --retry"
