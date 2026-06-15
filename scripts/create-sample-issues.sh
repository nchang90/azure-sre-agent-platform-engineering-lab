#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  echo "Usage: bash scripts/create-sample-issues.sh OWNER/REPO" >&2; exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh CLI not found. Install: brew install gh  |  winget install GitHub.cli" >&2; exit 1
fi

echo "Filing sample issues in $REPO …"

gh issue create --repo "$REPO" \
  --title "[Customer Issue] orders-api 500s spiked after CHG0030001 last night" \
  --body "$(cat <<'EOF'
## Customer Report

Starting around 22:00 UTC, we saw a surge of HTTP 500 errors from the orders-api. This coincided with what looked like a new deployment.

**Change request mentioned:** CHG0030001

**Impact:** ~15% of order requests failing. Revenue impact estimated.

**Steps to reproduce:** Call POST /api/orders repeatedly during peak hours.

Please investigate and advise.
EOF
)"

gh issue create --repo "$REPO" \
  --title "[Customer Issue] Checkout intermittently failing — possibly related to CHG0030002" \
  --body "$(cat <<'EOF'
## Customer Report

We're seeing intermittent checkout failures over the past 6 hours. Our on-call engineer believes it may be related to a scheduled maintenance window.

**Change request mentioned:** CHG0030002

**Impact:** ~5% of checkout attempts failing with 500. Users see "Something went wrong".

No rollback has been done yet. Awaiting SRE guidance.
EOF
)"

gh issue create --repo "$REPO" \
  --title "[Customer Issue] Deploy without a linked CR got through — paved road issue" \
  --body "$(cat <<'EOF'
## Customer Report

Our security team flagged that a deployment to orders-api happened outside of the ServiceNow change process. There was no linked CR at the time of deploy.

**Change request mentioned:** none

**Concern:** Paved road policy requires all production deploys to have an approved CR. How did this get through? What controls exist?

Please review and explain.
EOF
)"

gh issue create --repo "$REPO" \
  --title "[Customer Issue] Who owns change-management-runbook.md?" \
  --body "$(cat <<'EOF'
## Customer Report

We referenced the change-management-runbook.md during an incident last week and noticed some steps seem outdated (still references the old approval process).

**Change request mentioned:** none

**Ask:** Who is the DRI for this runbook? When was it last reviewed? Can we get it updated?
EOF
)"

echo
echo "✅ Filed 4 sample issues in $REPO"
echo "   The issue-triager scheduled task will process them within 12 hours,"
echo "   or trigger it manually from the SRE Agent portal."
