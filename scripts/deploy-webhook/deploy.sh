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
#   DB_PATH     - central SQLite DB      (default $DEPLOY_DIR/data/ghosts.db)
#   BACKUP_DIR  - SQLite backup dir      (default $DEPLOY_DIR/data/backups)

set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/odisea-deploy/Odisea}"
REPO_URL="${REPO_URL:-git@github.com:icarito/Odisea.git}"
BRANCH="${BRANCH:-main}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/anna-central}"
SERVICE="${SERVICE:-odisea-central.service}"
DB_PATH="${DB_PATH:-${CENTRAL_SQLITE_DB:-$DEPLOY_DIR/data/ghosts.db}}"
BACKUP_DIR="${BACKUP_DIR:-$DEPLOY_DIR/data/backups}"

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

log "backing up and migrating SQLite ($DB_PATH)"
python3 - "$DB_PATH" "$BACKUP_DIR" <<'PY'
import os
import sqlite3
import sys
import time

db_path = sys.argv[1]
backup_dir = sys.argv[2]
os.makedirs(os.path.dirname(db_path), exist_ok=True)
os.makedirs(backup_dir, exist_ok=True)

backup_path = ""

try:
    db_exists = os.path.exists(db_path)
    conn = sqlite3.connect(db_path)

    if db_exists:
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
    else:
        print("SQLite DB missing; creating fresh DB:", db_path)

    integrity = conn.execute("PRAGMA integrity_check").fetchone()
    if not integrity or integrity[0] != "ok":
        raise RuntimeError("integrity_check failed: %r" % (integrity,))

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS hotzones (
            id TEXT PRIMARY KEY,
            player_id TEXT,
            session_id TEXT,
            timestamp REAL,
            file_path TEXT,
            trigger_type TEXT DEFAULT 'auto'
        );
        """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS heartbeats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id TEXT,
            session_id TEXT,
            timestamp REAL,
            scene TEXT,
            platform TEXT,
            fps REAL,
            memory_mb REAL,
            pos_x REAL,
            pos_y REAL,
            pos_z REAL,
            engine_version TEXT,
            game_version TEXT,
            git_commit TEXT,
            build_id TEXT,
            build_channel TEXT,
            official_host TEXT,
            peer_id TEXT,
            UNIQUE(player_id, session_id, timestamp)
        );
        """
    )
    for column in ("game_version", "git_commit", "build_id", "build_channel", "official_host"):
        try:
            conn.execute("ALTER TABLE heartbeats ADD COLUMN %s TEXT" % column)
        except sqlite3.OperationalError as exc:
            if "duplicate column name" not in str(exc).lower():
                raise
    conn.commit()

    cols = {
        row[1]
        for row in conn.execute("PRAGMA table_info(hotzones)").fetchall()
    }
    required = {"id", "player_id", "session_id", "timestamp", "file_path", "trigger_type"}
    missing = sorted(required - cols)
    if missing:
        raise RuntimeError("hotzones schema missing columns: %s" % ", ".join(missing))

    hb_cols = {
        row[1]
        for row in conn.execute("PRAGMA table_info(heartbeats)").fetchall()
    }
    hb_required = {"game_version", "git_commit", "build_id", "build_channel", "official_host"}
    hb_missing = sorted(hb_required - hb_cols)
    if hb_missing:
        raise RuntimeError("heartbeats schema missing columns: %s" % ", ".join(hb_missing))

    post_integrity = conn.execute("PRAGMA integrity_check").fetchone()
    if not post_integrity or post_integrity[0] != "ok":
        raise RuntimeError("post-migration integrity_check failed: %r" % (post_integrity,))

    conn.close()
    print("SQLite migration OK:", db_path)
except Exception as exc:
    print("SQLite migration FAILED:", exc, file=sys.stderr)
    if backup_path:
        print("Backup left untouched:", backup_path, file=sys.stderr)
    sys.exit(1)
PY

log "deploying to $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/static"
mkdir -p "$DEPLOY_DIR/scripts"
cp "$REPO_DIR/odisea_central.py" "$DEPLOY_DIR/odisea_central.py"
cp "$REPO_DIR/scripts/import_ghosts_to_sqlite.py" "$DEPLOY_DIR/scripts/import_ghosts_to_sqlite.py"
cp "$REPO_DIR/scripts/import_nginx_geo.py" "$DEPLOY_DIR/scripts/import_nginx_geo.py"
chmod +x "$DEPLOY_DIR/scripts/import_nginx_geo.py"
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
