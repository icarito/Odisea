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

DEPLOY_LOCK   ?= $(DEPLOY_DIR)/.deploy.lock
DEPLOY_STAGE  ?= $(DEPLOY_DIR)/static/.dashboard.stage

deploy-dashboard: DEPLOY_VERSION := dev-$(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)-$(shell date -u +%H%M%S)
deploy-dashboard:
	@echo "==> Construyendo dashboard (version $(DEPLOY_VERSION))..."
	@# A unique version per manual deploy: embeds into the bundle (VITE_*) so its
	@# content hash changes even with no code change, and is reported by /health
	@# (version.conf below) — together they make the open dashboard reload + toast.
	cd dashboard && pnpm install --frozen-lockfile && \
		VITE_DASHBOARD_VERSION="$(DEPLOY_VERSION)" pnpm run build
	@echo "==> Backup + integrity-check del SQLite ..."
	@# Schema creation/migration is owned by odisea_central.py (it CREATEs tables
	@# and ALTERs columns on startup, which the restart below always triggers), so
	@# we don't duplicate it here. We only take a timestamped backup and verify the
	@# DB is intact before swapping in the new code.
	printf '%s\n' \
		'import os, sqlite3, time' \
		'db = "$(DEPLOY_DB)"' \
		'backup_dir = "$(DEPLOY_BACKUP_DIR)"' \
		'os.makedirs(os.path.dirname(db), exist_ok=True)' \
		'os.makedirs(backup_dir, exist_ok=True)' \
		'if os.path.exists(db):' \
		'    bpath = os.path.join(backup_dir, "ghosts_%s.db" % time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))' \
		'    src = sqlite3.connect(db); dst = sqlite3.connect(bpath); src.backup(dst); dst.close()' \
		'    if not os.path.exists(bpath) or os.path.getsize(bpath) <= 0: raise RuntimeError("backup failed")' \
		'    ok = src.execute("PRAGMA integrity_check").fetchone()' \
		'    src.close()' \
		'    if not ok or ok[0] != "ok": raise RuntimeError("integrity_check failed: %r" % (ok,))' \
		'    print("SQLite backup OK:", bpath)' \
		'else:' \
		'    print("SQLite no existe aún; el central lo creará al iniciar:", db)' \
		| ssh "$(DEPLOY_HOST)" python3 -
	@echo "==> Subiendo a staging $(DEPLOY_HOST):$(DEPLOY_STAGE) ..."
	ssh "$(DEPLOY_HOST)" 'mkdir -p "$(DEPLOY_STAGE)"'
	rsync -az --delete dashboard/dist/ "$(DEPLOY_HOST):$(DEPLOY_STAGE)/"
	rsync -az odisea_central.py "$(DEPLOY_HOST):$(DEPLOY_DIR)/odisea_central.py.new"
	@echo "==> Swap atómico + restart (bajo flock, serializado con el webhook) ..."
	@# Critical section in ONE ssh session under an exclusive flock on the shared
	@# lockfile (the webhook deploy takes the same lock). The static swap is an
	@# atomic `mv`, so index.html and its hashed assets are never mismatched.
	ssh "$(DEPLOY_HOST)" 'set -e; \
		exec 9>"$(DEPLOY_LOCK)"; \
		flock -w 600 9 || { echo "!! no pude tomar el lock de deploy en 10m"; exit 1; }; \
		mv "$(DEPLOY_DIR)/odisea_central.py.new" "$(DEPLOY_DIR)/odisea_central.py"; \
		rm -rf "$(DEPLOY_STATIC).old"; \
		if [ -d "$(DEPLOY_STATIC)" ]; then mv "$(DEPLOY_STATIC)" "$(DEPLOY_STATIC).old"; fi; \
		mv "$(DEPLOY_STAGE)" "$(DEPLOY_STATIC)"; \
		rm -rf "$(DEPLOY_STATIC).old"; \
		sudo mkdir -p "/etc/systemd/system/$(DEPLOY_SERVICE).d"; \
		printf "[Service]\nEnvironment=ODISEA_DASHBOARD_VERSION=%s\n" "$(DEPLOY_VERSION)" | sudo tee "/etc/systemd/system/$(DEPLOY_SERVICE).d/version.conf" >/dev/null; \
		sudo systemctl daemon-reload; \
		sudo systemctl restart $(DEPLOY_SERVICE); \
		sleep 2; \
		systemctl is-active --quiet $(DEPLOY_SERVICE) && echo "OK: servicio activo" || { echo "!! servicio no activo"; sudo journalctl -u $(DEPLOY_SERVICE) -n 20 --no-pager; exit 1; }'
	@echo "==> Dashboard desplegado: https://odisea.educa.juegos/"

.PHONY: all export-linux-arm64 export-pck export export-web-threads deploy-netlify web dashboard-dev-central deploy-dashboard
