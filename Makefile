# Makefile para Odisea Digest

GODOT ?= godot3-bin
EXPORT_FLAGS := --no-window
NETLIFY_SITE_ID ?= $$(grep NETLIFY_SITE_ID .env 2>/dev/null | cut -d= -f2)
NETLIFY_AUTH_TOKEN ?= $$(grep NETLIFY_AUTH_TOKEN .env 2>/dev/null | cut -d= -f2)

export-web-threads:
	$(GODOT) --path . $(EXPORT_FLAGS) --export "HTML5 Threads" build/index.html
	python3 scripts/minimize_html_export.py build/
	@echo "Export complete: build/"

deploy-netlify: export-web-threads
	@[ -n "$(NETLIFY_AUTH_TOKEN)" ] || (echo "ERROR: NETLIFY_AUTH_TOKEN not set. Check .env" && exit 1)
	@[ -n "$(NETLIFY_SITE_ID)" ] || (echo "ERROR: NETLIFY_SITE_ID not set. Check .env" && exit 1)
	NETLIFY_AUTH_TOKEN=$(NETLIFY_AUTH_TOKEN) NETLIFY_SITE_ID=$(NETLIFY_SITE_ID) \
		netlify deploy --dir=build --prod --message "Manual deploy $$(git rev-parse --short HEAD 2>/dev/null || echo local)"

web: deploy-netlify

render:
	gitingest ~/Proyectos/Odisea_Game/src -e addons/ -i "*.gd,*.md,*.oys" -e "replays/,reports/,archive/"

export-linux-arm64:
	$(GODOT) --path . $(EXPORT_FLAGS) --export "Linux/X11 ARM64" ports/third.arm64

export-pck:
	$(GODOT) --path . $(EXPORT_FLAGS) --export-pack "Linux/X11 ARM64" ports/third.pck

export: export-linux-arm64 export-pck
	@echo "Exported to ports/third.arm64 and ports/third.pck"

all: render

dashboard-dev:
	@set -a; \
	[ ! -f .env ] || . ./.env; \
	set +a; \
	cd dashboard; \
	VITE_API_TARGET=https://odisea.educa.juegos pnpm run dev

# Build local del dashboard y copia directa por ssh/rsync al servidor donde
# vive el servicio bridge (odisea-central). No depende del git del server.
# El central sirve los estáticos desde static/dashboard.
DEPLOY_HOST   ?= ubuntu@odisea.educa.juegos
DEPLOY_DIR    ?= /home/ubuntu/anna-central
DEPLOY_STATIC ?= $(DEPLOY_DIR)/static/dashboard
DEPLOY_DB     ?= $(DEPLOY_DIR)/data/ghosts.db
DEPLOY_BACKUP_DIR ?= $(DEPLOY_DIR)/data/backups
DEPLOY_SERVICE ?= odisea-central.service

deploy-dashboard:
	@echo "==> Construyendo dashboard..."
	cd dashboard && pnpm install --frozen-lockfile && pnpm run build
	@echo "==> Preparando backup/migración SQLite en $(DEPLOY_HOST):$(DEPLOY_DB) ..."
	ssh "$(DEPLOY_HOST)" 'set -e; \
		mkdir -p "$(DEPLOY_BACKUP_DIR)"; \
		if [ -f "$(DEPLOY_DB)" ]; then \
			backup="$(DEPLOY_BACKUP_DIR)/ghosts_$$(date -u +%Y%m%dT%H%M%SZ).db"; \
			cp "$(DEPLOY_DB)" "$$backup"; \
			echo "Backup SQLite: $$backup"; \
		else \
			echo "SQLite no existe aún: $(DEPLOY_DB)"; \
		fi'
	printf '%s\n' \
		'import os, sqlite3' \
		'db = "$(DEPLOY_DB)"' \
		'os.makedirs(os.path.dirname(db), exist_ok=True)' \
		'conn = sqlite3.connect(db)' \
		'conn.execute("""CREATE TABLE IF NOT EXISTS hotzones (id TEXT PRIMARY KEY, player_id TEXT, session_id TEXT, timestamp REAL, file_path TEXT, trigger_type TEXT DEFAULT '"'"'auto'"'"');""")' \
		'conn.execute("""CREATE TABLE IF NOT EXISTS heartbeats (id INTEGER PRIMARY KEY AUTOINCREMENT, player_id TEXT, session_id TEXT, timestamp REAL, scene TEXT, platform TEXT, fps REAL, memory_mb REAL, pos_x REAL, pos_y REAL, pos_z REAL, engine_version TEXT, game_version TEXT, git_commit TEXT, build_id TEXT, build_channel TEXT, official_host TEXT, peer_id TEXT, UNIQUE(player_id, session_id, timestamp));""")' \
		'for c in ["game_version", "git_commit", "build_id", "build_channel", "official_host"]:' \
		'    try: conn.execute("ALTER TABLE heartbeats ADD COLUMN %s TEXT" % c)' \
		'    except sqlite3.OperationalError as e:' \
		'        if "duplicate column name" not in str(e).lower(): raise' \
		'try: conn.execute("ALTER TABLE heartbeats ADD COLUMN focused INTEGER DEFAULT 1")' \
		'except sqlite3.OperationalError as e:' \
		'    if "duplicate column name" not in str(e).lower(): raise' \
		'conn.commit()' \
		'conn.close()' \
		'print("Migración central OK:", db)' \
		| ssh "$(DEPLOY_HOST)" python3 -
	@echo "==> Desplegando odisea_central.py -> $(DEPLOY_HOST):$(DEPLOY_DIR) ..."
	rsync -az odisea_central.py "$(DEPLOY_HOST):$(DEPLOY_DIR)/odisea_central.py"
	@echo "==> Sincronizando dist/ -> $(DEPLOY_HOST):$(DEPLOY_STATIC) ..."
	rsync -az --delete dashboard/dist/ "$(DEPLOY_HOST):$(DEPLOY_STATIC)/"
	@echo "==> Reiniciando $(DEPLOY_SERVICE)..."
	ssh "$(DEPLOY_HOST)" 'sudo systemctl restart $(DEPLOY_SERVICE) && sleep 2 && systemctl is-active --quiet $(DEPLOY_SERVICE) && echo "OK: servicio activo" || (echo "!! servicio no activo" && sudo journalctl -u $(DEPLOY_SERVICE) -n 20 --no-pager && exit 1)'
	@echo "==> Dashboard desplegado: https://odisea.educa.juegos/"

.PHONY: all export-linux-arm64 export-pck export export-web-threads deploy-netlify web dashboard-dev-central deploy-dashboard
