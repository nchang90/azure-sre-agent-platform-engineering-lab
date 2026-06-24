#!/usr/bin/env bash

servicenow_integration_ready() {
  [[ -n "${SERVICENOW_INSTANCE_URL:-}" ]] && [[ -n "${SERVICENOW_USERNAME:-}" ]] && [[ -n "${SERVICENOW_PASSWORD:-}" ]]
}

setup_servicenow_integration() {
  local normalized connector_body code endpoint

  if ! servicenow_integration_ready; then
    warn "Skipping ServiceNow integration (set SERVICENOW_INSTANCE_URL, SERVICENOW_USERNAME, and SERVICENOW_PASSWORD to enable it)."
    return 0
  fi

  if [[ ! "${SERVICENOW_INSTANCE_URL}" =~ ^https:// ]]; then
    die "SERVICENOW_INSTANCE_URL must start with https://"
  fi

  normalized="${SERVICENOW_INSTANCE_URL%/}"
  endpoint="$normalized/api/sn_mcp/mcp"

  connector_body="$(jq -nc \
    --arg endpoint "$endpoint" \
    --arg username "$SERVICENOW_USERNAME" \
    --arg password "$SERVICENOW_PASSWORD" \
    '{
      name:"servicenow",
      type:"AgentConnector",
      properties:{
        dataConnectorType:"Mcp",
        dataSource:$endpoint,
        identity:"",
        extendedProperties:{
          type:"http",
          endpoint:$endpoint,
          authType:"CustomHeaders",
          headers:{
            Authorization:("Basic " + (($username + ":" + $password) | @base64))
          }
        }
      }
    }')"

  code="$(api PUT /api/v2/extendedAgent/connectors/servicenow \
    -H "Content-Type: application/json" \
    --data-binary "$connector_body")"
  require_json_body "ServiceNow connector upsert" "$code"
  ok "  ServiceNow connector created"

  code="$(api GET /api/v2/extendedAgent/connectors/servicenow)"
  require_json_body "ServiceNow connector fetch" "$code"

  if [[ "$(jq -r '.properties.dataConnectorType // empty' "$RESP")" != "Mcp" ]]; then
    warn "ServiceNow connector returned an unexpected connector type."
  fi
  if [[ "$(jq -r '.properties.extendedProperties.endpoint // empty' "$RESP")" != "$endpoint" ]]; then
    warn "ServiceNow connector endpoint did not round-trip as expected."
  fi
}
