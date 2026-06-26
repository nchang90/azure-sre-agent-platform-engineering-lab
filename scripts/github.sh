#!/usr/bin/env bash

github_oauth_configured() {
  local code configured

  code="$(api GET /api/v2/github/domains)"
  if is_ok_status "$code" && jq -e . "$RESP" >/dev/null 2>&1; then
    configured="$(jq -r '
      any((.values // [])[]?;
        (.isConfigured == true)
        or (.isConnected == true)
        or ((.authType // "" | ascii_downcase) == "pat")
        or (((.authType // "" | ascii_downcase) == "oauth") and ((.expiresOn // "") != ""))
      ) | tostring
    ' "$RESP" 2>/dev/null || echo "false")"
    [[ "$configured" == "true" ]] && return 0
  fi

  code="$(api GET /api/v1/Github/auth/status)"
  if is_ok_status "$code" && jq -e . "$RESP" >/dev/null 2>&1; then
    configured="$(jq -r '(.isConfigured // .hosts[0].isConfigured // false) | tostring' "$RESP" 2>/dev/null || echo "false")"
    [[ "$configured" == "true" ]] && return 0
  fi

  return 1
}

github_oauth_url() {
  local code url

  code="$(api GET /api/v2/github/oauth/config)"
  if is_ok_status "$code" && jq -e . "$RESP" >/dev/null 2>&1; then
    url="$(jq -r '.oAuthUrl // .OAuthUrl // empty' "$RESP" 2>/dev/null || true)"
    [[ -n "$url" ]] && {
      echo "$url"
      return 0
    }
  fi

  code="$(api GET /api/v1/Github/config)"
  if is_ok_status "$code" && jq -e . "$RESP" >/dev/null 2>&1; then
    url="$(jq -r '.oAuthUrl // .OAuthUrl // empty' "$RESP" 2>/dev/null || true)"
    [[ -n "$url" ]] && {
      echo "$url"
      return 0
    }
  fi

  return 1
}

setup_github_integration() {
  local p REPO_OWNER REPO_NAME code OAUTH_URL wait_secs attempts attempt
  local GITHUB_AUTH_READY repo_body
  local CLONE_STATUS REPO_ERROR repo_wait_secs repo_poll_attempts

  # Always clean stale/default repo aliases so disconnected placeholders do not linger.
  for p in /api/v2/repos/github /api/v1/repos/github /api/v1/codeRepos/github /api/v1/codeRepositories/github; do
    best_effort_delete "$p"
  done

  if [[ "$ENABLE_GITHUB_INTEGRATION" != "true" ]]; then
    warn "Step 5/5: Skipping GitHub integration (set ENABLE_GITHUB_INTEGRATION=true to enable)."
    return 0
  fi

  log "Step 5/5: GitHub integration..."
  if [[ ! "$GITHUB_REPO" =~ ^[^/]+/[^/]+$ ]]; then
    die "GITHUB_REPO must be in 'owner/repo' format (current: $GITHUB_REPO)"
  fi
  REPO_OWNER="${GITHUB_REPO%%/*}"
  REPO_NAME="${GITHUB_REPO##*/}"

  if [[ -n "$GITHUB_PAT" ]]; then
    log "  Installing GitHub PAT auth..."
    code="$(api PUT /api/v2/github/domains/github.com \
      -H "Content-Type: application/json" \
      --data-binary "{\"AuthType\":\"Pat\",\"Pat\":\"${GITHUB_PAT}\"}")"
    if is_ok_status "$code"; then
      ok "  GitHub PAT auth configured"
    else
      warn "  GitHub PAT auth returned HTTP $code"
    fi
  fi

  GITHUB_AUTH_READY="false"
  if [[ -n "$GITHUB_PAT" ]]; then
    # PAT mode (starter-lab style): PAT is the auth materialization path,
    # so skip OAuth state polling which can fail behind callback/session issues.
    GITHUB_AUTH_READY="true"
    ok "  Using GitHub PAT auth mode"
  elif github_oauth_configured; then
    GITHUB_AUTH_READY="true"
  else
    OAUTH_URL="$(github_oauth_url || true)"
    if [[ -n "$OAUTH_URL" ]]; then
      echo
      echo "  GitHub OAuth sign-in required:"
      echo "    $OAUTH_URL"
      echo "  Approve access, then this script will continue automatically."
    else
      warn "Could not fetch OAuth URL. Open portal and connect GitHub manually."
    fi

    wait_secs="${GITHUB_OAUTH_WAIT_SECONDS}"
    if ! [[ "$wait_secs" =~ ^[0-9]+$ ]] || [[ "$wait_secs" -lt 10 ]]; then
      wait_secs=240
    fi
    attempts=$((wait_secs / 10))
    [[ "$attempts" -lt 1 ]] && attempts=1

    for attempt in $(seq 1 "$attempts"); do
      sleep 10
      auth
      if github_oauth_configured; then
        GITHUB_AUTH_READY="true"
        ok "  GitHub OAuth authorized"
        break
      fi
      echo "  ... waiting for GitHub authorization (${attempt}/$attempts)"
    done
  fi

  if [[ "$GITHUB_AUTH_READY" != "true" ]]; then
    if [[ "$STRICT_GITHUB_OAUTH_CHECK" == "true" ]]; then
      echo
      err "GitHub OAuth is not connected for this agent."
      if [[ -n "$AGENT_PORTAL_URL" ]]; then
        echo "  Open: $AGENT_PORTAL_URL"
      else
        echo "  Open: https://sre.azure.com"
      fi
      echo "  Then connect GitHub in the agent settings and re-run this script."
      die "Stopping because PR/push operations will remain blocked until OAuth is connected."
    fi
    warn "GitHub OAuth is still not confirmed; proceeding in non-strict mode."
  fi

  auth
  repo_body="$(cat <<EOF
{"name":"${REPO_NAME}","type":"CodeRepo","properties":{"url":"https://github.com/${REPO_OWNER}/${REPO_NAME}","type":"GitHub"}}
EOF
)"
  api_json "Code repo upsert" PUT "/api/v2/repos/${REPO_NAME}" "$repo_body"

  repo_wait_secs="${GITHUB_REPO_STATUS_WAIT_SECONDS:-60}"
  if ! [[ "$repo_wait_secs" =~ ^[0-9]+$ ]] || [[ "$repo_wait_secs" -lt 10 ]]; then
    repo_wait_secs=60
  fi
  repo_poll_attempts=$((repo_wait_secs / 5))
  [[ "$repo_poll_attempts" -lt 1 ]] && repo_poll_attempts=1

  for attempt in $(seq 1 "$repo_poll_attempts"); do
    code="$(api GET /api/v2/repos)"
    require_json_body "Code repo list" "$code"
    CLONE_STATUS="$(jq -r --arg name "$REPO_NAME" '.value[]? | select(.name==$name) | .properties.cloneStatus // empty' "$RESP" | head -n1)"
    REPO_ERROR="$(jq -r --arg name "$REPO_NAME" '.value[]? | select(.name==$name) | .properties.errorMessage // empty' "$RESP" | head -n1)"

    if [[ "$CLONE_STATUS" == "Ready" && -z "$REPO_ERROR" ]]; then
      break
    fi

    if [[ "$attempt" -lt "$repo_poll_attempts" ]]; then
      echo "  ... waiting for repo materialization (${attempt}/$repo_poll_attempts)"
      sleep 5
      auth
    fi
  done

  if [[ "$CLONE_STATUS" == "Ready" && -z "$REPO_ERROR" ]]; then
    ok "  Code repo: $GITHUB_REPO"
    return 0
  fi

  if [[ -z "$CLONE_STATUS" && -z "$REPO_ERROR" ]]; then
    log "  Repo status is still materializing and no error is reported; continuing."
    ok "  Code repo: $GITHUB_REPO"
    return 0
  fi

  err "Repo '${REPO_NAME}' did not become ready (cloneStatus='${CLONE_STATUS:-<empty>}', error='${REPO_ERROR:-<empty>}')."
  die "GitHub auth may not be materialized; reconnect OAuth/PAT and re-run post-provision."
}
