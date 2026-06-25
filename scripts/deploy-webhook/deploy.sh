#!/bin/bash
#
# Auto-deploy script triggered by the /webhook/deploy endpoint in odisea_central.py.
#
# It keeps a DEDICATED clone (separate from the interactive ~/.openclaw workspace),
# hard-resets it to origin/main, builds the external Expo dashboard, copies the
# central + static assets into the runtime dir (~/anna-central), and restarts the
# systemd service.
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
#   REPO_DIR       - Odisea clone          (default ~/odisea-deploy/Odisea)
#   REPO_URL       - Odisea remote         (default git@github.com:icarito/Odisea.git)
#   DASHBOARD_DIR  - dashboard clone       (default ~/odisea-deploy/Odisea_Dashboard)
#   DASHBOARD_URL  - dashboard remote      (default https://github.com/icarito/Rottapaint)
#   BRANCH         - branch to deploy      (default main)
#   DEPLOY_DIR     - runtime dir           (default ~/anna-central)
#   SERVICE        - systemd unit          (default odisea-central.service)
#   DB_PATH        - central SQLite DB     (default $DEPLOY_DIR/data/ghosts.db)
#   BACKUP_DIR     - SQLite backup dir     (default $DEPLOY_DIR/data/backups)

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/odisea-deploy/Odisea}"
REPO_URL="${REPO_URL:-git@github.com:icarito/Odisea.git}"
DASHBOARD_DIR="${DASHBOARD_DIR:-$HOME/odisea-deploy/Odisea_Dashboard}"
DASHBOARD_URL="${DASHBOARD_URL:-https://github.com/icarito/Rottapaint}"
BRANCH="${BRANCH:-main}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/anna-central}"
SERVICE="${SERVICE:-odisea-central.service}"
DB_PATH="${DB_PATH:-${CENTRAL_SQLITE_DB:-$DEPLOY_DIR/data/ghosts.db}}"
BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/data/backups}"

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# Serialize deploys: the webhook (origin/main) and a manual `make deploy-dashboard`
# both write $DEPLOY_DIR/static/dashboard. Running concurrently leaves index.html
# pointing at hashed assets the other deploy already replaced (→ 404 / corrupted
# content). Take an exclusive lock on a shared lockfile for the whole run; the
# manual Makefile path takes the SAME lock. We re-exec under flock so the lock is
# held for the entire script, then released when it exits.
LOCK_FILE="${DEPLOY_LOCK:-$DEPLOY_DIR/.deploy.lock}"
if [ -z "${_DEPLOY_LOCKED:-}" ]; then
  mkdir -p "$(dirname "$LOCK_FILE")"
  export _DEPLOY_LOCKED=1
  # -w 600: wait up to 10 min for a concurrent deploy to finish rather than fail.
  exec flock -w 600 "$LOCK_FILE" "$0" "$@"
fi

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
FULL_SHA="$(git rev-parse HEAD)"
log "now at $NEW_SHA"

if [ ! -d "$DASHBOARD_DIR/.git" ]; then
  log "no dashboard clone at $DASHBOARD_DIR, cloning from $DASHBOARD_URL"
  git clone "$DASHBOARD_URL" "$DASHBOARD_DIR"
fi

cd "$DASHBOARD_DIR"
log "fetching dashboard origin"
git fetch --prune origin
log "hard-resetting dashboard to origin/$BRANCH"
git checkout -q "$BRANCH" 2>/dev/null || git checkout -q -b "$BRANCH" "origin/$BRANCH"
git reset --hard "origin/$BRANCH"
DASHBOARD_SHA="$(git rev-parse --short HEAD)"
DASHBOARD_FULL_SHA="$(git rev-parse HEAD)"
log "dashboard now at $DASHBOARD_SHA"

log "building Expo dashboard (npm)"
npm ci
EXPO_PUBLIC_DASHBOARD_VERSION="$DASHBOARD_SHA" \
EXPO_PUBLIC_GIT_COMMIT="$DASHBOARD_FULL_SHA" \
npm run build:web

log "backing up SQLite ($DB_PATH)"
# Schema (CREATE TABLE / ALTER ADD COLUMN) is owned by odisea_central.py, which
# re-applies it on every startup (the restart below). We do NOT duplicate it here.
# This block only: backs up the DB, integrity-checks it, and runs the legacy
# data backfills the central does not do (intake_mode default, official_build).
python3 - "$DB_PATH" "$BACKUP_DIR" <<'PY'
import os
import sqlite3
import sys
import time

db_path = sys.argv[1]
backup_dir = sys.argv[2]
os.makedirs(os.path.dirname(db_path), exist_ok=True)
os.makedirs(backup_dir, exist_ok=True)

try:
    if not os.path.exists(db_path):
        print("SQLite DB missing; the central will create it on startup:", db_path)
        sys.exit(0)

    conn = sqlite3.connect(db_path)

    backup_path = os.path.join(
        backup_dir,
        "ghosts_%s.db" % time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
    )
    backup = sqlite3.connect(backup_path)
    conn.backup(backup)
    backup.close()
    if not os.path.exists(backup_path) or os.path.getsize(backup_path) <= 0:
        raise RuntimeError("backup file was not created correctly")
    print("SQLite backup:", backup_path)

    integrity = conn.execute("PRAGMA integrity_check").fetchone()
    if not integrity or integrity[0] != "ok":
        raise RuntimeError("integrity_check failed: %r" % (integrity,))

    # Legacy data backfills (no-ops once applied; the central doesn't do these).
    # Guarded by table_info so they don't fail on a DB the central hasn't built yet.
    hb_cols = {row[1] for row in conn.execute("PRAGMA table_info(heartbeats)").fetchall()}
    if "intake_mode" in hb_cols:
        conn.execute("UPDATE heartbeats SET intake_mode='telemetry' WHERE intake_mode IS NULL OR intake_mode=''")
    if {"official_build", "official_host", "build_channel"} <= hb_cols:
        conn.execute(
            """
            UPDATE heartbeats
               SET official_build=1
             WHERE COALESCE(official_build, 0)=0
               AND (COALESCE(official_host, '') != ''
                    OR COALESCE(build_channel, '') IN ('nightly', 'tip', 'release'))
            """
        )
    conn.commit()
    conn.close()
    print("SQLite backup + backfill OK:", db_path)
except Exception as exc:
    print("SQLite backup/backfill FAILED:", exc, file=sys.stderr)
    sys.exit(1)
PY

log "deploying to $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/static"
mkdir -p "$DEPLOY_DIR/scripts"
cp "$REPO_DIR/odisea_central.py" "$DEPLOY_DIR/odisea_central.py"
cp "$REPO_DIR/scripts/import_ghosts_to_sqlite.py" "$DEPLOY_DIR/scripts/import_ghosts_to_sqlite.py"
cp "$REPO_DIR/scripts/import_nginx_geo.py" "$DEPLOY_DIR/scripts/import_nginx_geo.py"
chmod +x "$DEPLOY_DIR/scripts/import_nginx_geo.py"
# Atomic static swap: copy into a staging dir on the same filesystem, then `mv`
# into place. A plain rm+cp leaves a window where index.html references hashed
# assets that aren't there yet (→ 404 / corrupted content). The mv is atomic.
STAGE="$DEPLOY_DIR/static/.dashboard.stage"
rm -rf "$STAGE" "$DEPLOY_DIR/static/dashboard.old"
cp -r "$DASHBOARD_DIR/dist" "$STAGE"
[ -d "$DEPLOY_DIR/static/dashboard" ] && mv "$DEPLOY_DIR/static/dashboard" "$DEPLOY_DIR/static/dashboard.old"
mv "$STAGE" "$DEPLOY_DIR/static/dashboard"
rm -rf "$DEPLOY_DIR/static/dashboard.old"

log "writing systemd build metadata"
sudo mkdir -p "/etc/systemd/system/${SERVICE}.d"
sudo tee "/etc/systemd/system/${SERVICE}.d/version.conf" >/dev/null <<EOF
[Service]
Environment=ODISEA_DASHBOARD_VERSION=$NEW_SHA
Environment=GITHUB_SHA=$FULL_SHA
Environment=ODISEA_EXPO_DASHBOARD_VERSION=$DASHBOARD_SHA
Environment=ODISEA_EXPO_DASHBOARD_SHA=$DASHBOARD_FULL_SHA
EOF
sudo systemctl daemon-reload

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
