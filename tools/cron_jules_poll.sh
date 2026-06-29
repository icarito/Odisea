#!/usr/bin/env bash
# cron_jules_poll.sh — Polled by cron, bypasses model inference entirely.
# Outputs a single-line status for the given Jules session.
set -euo pipefail

JULES_CLI="/home/ubuntu/.openclaw/workspace/agents/odisea-consultant/bin/jules-cli"
SESSION_ID="${1:-}"

if [ -z "$SESSION_ID" ]; then
  echo "Usage: $0 <session_id>"
  exit 1
fi

OUTPUT=$("$JULES_CLI" status "$SESSION_ID" 2>&1)
STATE=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('state','unknown'))")
ACTIVITY=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('latest_activity','none') or 'none')")
NEEDS_AT=$(echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('needs_attention',False))")

echo "JULES_SESSION=$SESSION_ID STATE=$STATE ACTIVITY=$ACTIVITY NEEDS_ATTENTION=$NEEDS_AT"

if [ "$STATE" = "COMPLETED" ]; then
  RESULT=$("$JULES_CLI" result "$SESSION_ID" 2>&1)
  PR_URL=$(echo "$RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); outs=d.get('outputs',[]); print(outs[0].get('pr_url','') if outs else 'no-output')")
  echo "RESULT_PR_URL=$PR_URL"
fi
