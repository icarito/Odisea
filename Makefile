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

dashboard-dev-central:
	@set -a; \
	[ ! -f .env ] || . ./.env; \
	set +a; \
	cd dashboard; \
	VITE_API_TARGET=https://odisea.educa.juegos pnpm run dev

.PHONY: all export-linux-arm64 export-pck export export-web-threads deploy-netlify web dashboard-dev-central
