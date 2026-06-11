#!/bin/bash
#
# Auto-deploy script triggered by the /webhook/deploy endpoint in odisea_central.py.
#
# It keeps a DEDICATED clone (separate from the interactive ~/.openclaw workspace),
# hard-resets it to origin/main, builds the dashboard, copies the central + static
# assets into the runtime dir (~/anna-central), and restarts the systemd service.
#
# Designed to run detached: it survives odisea-central restarting mid-deploy.
#
# Install on the server (one time):
#   mkdir -p ~/odisea-deploy
#   git clone git@github.com:icarito/Odisea.git ~/odisea-deploy/Odisea
#   cp ~/odisea-deploy/Odisea/scripts/deploy-webhook/deploy.sh ~/odisea-deploy/deploy.sh
#   chmod +x ~/odisea-deploy/deploy.sh
#   # allow the restart without a password prompt (see README)
#
# Override via env if your layout differs:
#   REPO_DIR    - dedicated clone        (default ~/odisea-deploy/Odisea)
#   REPO_URL    - remote for first clone (default git@github.com:icarito/Odisea.git)
#   BRANCH      - branch to deploy       (default main)
#   DEPLOY_DIR  - runtime dir            (default ~/anna-central)
#   SERVICE     - systemd unit           (default odisea-central.service)

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/odisea-deploy/Odisea}"
REPO_URL="${REPO_URL:-git@github.com:icarito/Odisea.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/anna-central}"
SERVICE="${SERVICE:-odisea-central.service}"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "=== auto-deploy start (branch=$BRANCH) ==="

# Clone on first run if the dedicated checkout doesn't exist yet.
if [ ! -d "$REPO_DIR/.git" ]; then
  log "no clone at $REPO_DIR, cloning from $REPO_URL"
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

log "fetching origin"
git fetch --prune origin

log "hard-resetting to origin/$BRANCH"
git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"

NEW_SHA="$(git rev-parse --short HEAD)"
log "now at $NEW_SHA"

log "building dashboard (pnpm)"
cd "$REPO_DIR/dashboard"
# The dashboard uses pnpm (pnpm-lock.yaml). npm is intentionally NOT used — it
# diverges from the pnpm lockfile. Resolve a pnpm command that works without
# root: a real pnpm on PATH, else corepack's shim (`corepack pnpm ...`).
# `corepack enable` needs write access to /usr/bin, which we don't have, so we
# invoke pnpm through corepack directly instead.
if command -v pnpm >/dev/null 2>&1; then
  PNPM="pnpm"
elif command -v corepack >/dev/null 2>&1; then
  corepack prepare "pnpm@${PNPM_VERSION:-9.15.0}" --activate >/dev/null 2>&1 || true
  PNPM="corepack pnpm"
else
  echo "::error::Neither pnpm nor corepack is available"; exit 1
fi
log "using: $PNPM ($($PNPM --version 2>/dev/null || echo '?'))"
$PNPM install --frozen-lockfile
$PNPM run build

log "deploying to $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/static"
cp "$REPO_DIR/odisea_central.py" "$DEPLOY_DIR/odisea_central.py"
rm -rf "$DEPLOY_DIR/static/dashboard"
cp -r "$REPO_DIR/dashboard/dist" "$DEPLOY_DIR/static/dashboard"

log "restarting $SERVICE"
sudo systemctl restart "$SERVICE"
sleep 2

if systemctl is-active --quiet "$SERVICE"; then
  log "OK: $SERVICE active at $NEW_SHA"
else
  log "ERROR: $SERVICE did not come back up"
  sudo journalctl -u "$SERVICE" -n 20 --no-pager || true
  exit 1
fi

log "=== auto-deploy done ($NEW_SHA) ==="
