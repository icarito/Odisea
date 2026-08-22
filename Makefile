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

# En Godot 3, BakedLightmap sólo puede hornearse dentro del editor. Abrí
# Dome_Intro.tscn y ejecutá tools/editor_bake_dome_intro_lightmap.gd; ese
# EditorScript invoca bake-lightmap-postprocess al terminar correctamente.
bake:
	$(GODOT) --path . $(EXPORT_FLAGS) -s tools/verify_dome_intro_contract.gd
	@echo "[bake] Abre Dome_Intro.tscn y ejecuta tools/editor_bake_dome_intro_lightmap.gd en Godot."

# Regeneración explícita de la geometría procedimental. No es parte del bake
# del lightmap: puede cambiar muchos recursos .mesh y debe correrse sólo al
# editar sus escenas fuente.
bake-dome-geometry:
	$(GODOT) --path . $(EXPORT_FLAGS) -s tools/bake_pipe_network.gd
	$(GODOT) --path . $(EXPORT_FLAGS) -s tools/bake_scaffold_walkways.gd
	$(GODOT) --path . $(EXPORT_FLAGS) -s tools/bake_dome_intro_hub_floors.gd
	$(GODOT) --path . $(EXPORT_FLAGS) -s tools/verify_dome_intro_contract.gd
	python3 scripts/check_tracked_imports.py

# Aplica el look cyan/oscuro a TODOS los PNG referenciados por el .lmbake recién
# recocido. Valores por defecto aproximan la referencia ya versionada; ajustar:
# make bake-lightmap-postprocess DOME_LIGHTMAP_BRIGHTNESS=18
DOME_LIGHTMAP_PATH ?=
DOME_LIGHTMAP_DATA_PATH ?= core_v2/levels/interiors/Dome_Intro.lmbake
DOME_LIGHTMAP_TINT ?= 008da3
DOME_LIGHTMAP_COLORIZE ?= 85
DOME_LIGHTMAP_BRIGHTNESS ?= 15
# El piso debe conservar contraste para leer la luz direccional y sus sombras.
DOME_LIGHTMAP_FLOOR_COLORIZE ?= 35
DOME_LIGHTMAP_FLOOR_BRIGHTNESS ?= 65
bake-lightmap-postprocess:
	DOME_LIGHTMAP_PATH="$(DOME_LIGHTMAP_PATH)" DOME_LIGHTMAP_DATA_PATH="$(DOME_LIGHTMAP_DATA_PATH)" \
	DOME_LIGHTMAP_TINT="$(DOME_LIGHTMAP_TINT)" DOME_LIGHTMAP_COLORIZE="$(DOME_LIGHTMAP_COLORIZE)" \
	DOME_LIGHTMAP_BRIGHTNESS="$(DOME_LIGHTMAP_BRIGHTNESS)" DOME_LIGHTMAP_FLOOR_COLORIZE="$(DOME_LIGHTMAP_FLOOR_COLORIZE)" \
	DOME_LIGHTMAP_FLOOR_BRIGHTNESS="$(DOME_LIGHTMAP_FLOOR_BRIGHTNESS)" DOME_LIGHTMAP_FORCE="$(DOME_LIGHTMAP_FORCE)" \
	sh tools/postprocess_dome_intro_lightmap.sh

# Reimporta solo los assets de escena importados para aplicar split_stream.
# Los .mesh nativos no pasan por el importador. Los artefactos se respaldan en
# build/split-stream-reimport-backup antes de abrir Godot en modo import.
reimport-split-stream-meshes:
	bash tools/prepare_split_stream_mesh_reimport.sh
	GODOT_BIN="$(GODOT)" bash tools/run_split_stream_mesh_reimport.sh
	bash tools/verify_split_stream_mesh_reimport.sh
	python3 scripts/check_tracked_imports.py
	python3 scripts/check_critical_import_artifacts.py

dashboard-dev:
	@set -a; \
	[ ! -f .env ] || . ./.env; \
	set +a; \
	cd dashboard; \
	VITE_API_TARGET=https://odisea.educa.juegos pnpm run dev

# Build local del dashboard y copia directa por ssh/rsync al servidor donde
# vive el servicio bridge (odisea-central). No depende del git del server.
# El central sirve los estáticos desde static/dashboard.
DEPLOY_HOST   ?= icarito@odisea.educa.juegos
DEPLOY_DIR    ?= /opt/odisea-central/repo
DEPLOY_STATIC ?= $(DEPLOY_DIR)/static/dashboard
DEPLOY_DB     ?= $(DEPLOY_DIR)/data/ghosts.db
DEPLOY_BACKUP_DIR ?= $(DEPLOY_DIR)/data/backups
DEPLOY_SERVICE ?= odisea-central.service
# El runtime vive en /opt y pertenece al usuario del servicio (no al del login):
# se entra por SSH como $(DEPLOY_HOST), pero TODO lo que escribe bajo $(DEPLOY_DIR)
# va por sudo y queda con este dueño. Cambiar ambos si se migra el servicio.
DEPLOY_OWNER  ?= nanoclaw:nanoclaw

DEPLOY_LOCK   ?= $(DEPLOY_DIR)/.deploy.lock
# El staging vive DENTRO de $(DEPLOY_DIR)/static a propósito: el swap final es un
# `mv`, que solo es atómico dentro del mismo filesystem. Un stage en /home o /tmp
# podría cruzar filesystem y degradar el mv a copia no atómica.
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
		| ssh "$(DEPLOY_HOST)" sudo python3 -
	@echo "==> Subiendo a staging $(DEPLOY_HOST):$(DEPLOY_STAGE) ..."
	@# rsync corre bajo el usuario de login, que NO puede escribir en $(DEPLOY_DIR):
	@# --rsync-path eleva solo el rsync remoto, sin sacar el staging de su filesystem.
	ssh "$(DEPLOY_HOST)" 'sudo mkdir -p "$(DEPLOY_STAGE)"'
	rsync -az --delete --rsync-path="sudo rsync" dashboard/dist/ "$(DEPLOY_HOST):$(DEPLOY_STAGE)/"
	rsync -az --rsync-path="sudo rsync" odisea_central.py "$(DEPLOY_HOST):$(DEPLOY_DIR)/odisea_central.py.new"
	@echo "==> Swap atómico + restart (bajo flock, serializado con el webhook) ..."
	@# Critical section in ONE ssh session under an exclusive flock on the shared
	@# lockfile (the webhook deploy takes the same lock). The static swap is an
	@# atomic `mv`, so index.html and its hashed assets are never mismatched.
	@# Va por `sudo bash -s`: el lockfile y $(DEPLOY_DIR) son de $(DEPLOY_OWNER), así
	@# que ni el flock se puede tomar sin privilegios. Se alimenta por stdin para no
	@# anidar comillas, igual que el bloque de SQLite de arriba.
	printf '%s\n' \
		'set -e' \
		'exec 9>"$(DEPLOY_LOCK)"' \
		'flock -w 600 9 || { echo "!! no pude tomar el lock de deploy en 10m"; exit 1; }' \
		'mv "$(DEPLOY_DIR)/odisea_central.py.new" "$(DEPLOY_DIR)/odisea_central.py"' \
		'rm -rf "$(DEPLOY_STATIC).old"' \
		'if [ -d "$(DEPLOY_STATIC)" ]; then mv "$(DEPLOY_STATIC)" "$(DEPLOY_STATIC).old"; fi' \
		'mv "$(DEPLOY_STAGE)" "$(DEPLOY_STATIC)"' \
		'rm -rf "$(DEPLOY_STATIC).old"' \
		'chown -R $(DEPLOY_OWNER) "$(DEPLOY_STATIC)" "$(DEPLOY_DIR)/odisea_central.py"' \
		'mkdir -p "/etc/systemd/system/$(DEPLOY_SERVICE).d"' \
		'printf "[Service]\nEnvironment=ODISEA_DASHBOARD_VERSION=%s\n" "$(DEPLOY_VERSION)" > "/etc/systemd/system/$(DEPLOY_SERVICE).d/version.conf"' \
		'systemctl daemon-reload' \
		'systemctl restart $(DEPLOY_SERVICE)' \
		'sleep 2' \
		'systemctl is-active --quiet $(DEPLOY_SERVICE) && echo "OK: servicio activo" || { echo "!! servicio no activo"; journalctl -u $(DEPLOY_SERVICE) -n 20 --no-pager; exit 1; }' \
		| ssh "$(DEPLOY_HOST)" sudo bash -s
	@echo "==> Dashboard desplegado: https://odisea.educa.juegos/"

# --- Android local debug build, signed with the real update key -----------
# `--export-debug` alone signs with a throwaway debug keystore (Godot's editor
# default, or the project's android/debug.keystore — either way NOT the key
# used to sign official builds). CI re-signs every published nightly with a
# persistent key so nightlies can update each other in place (see
# .github/workflows/export_all.yml, "Android Sign and Validate"). A
# throwaway-signed local build is a DIFFERENT signer: Android refuses to
# install it over an official nightly (or vice versa) without an uninstall,
# and it can never apply a real OTA update either — the exact thing an
# editor one-click "Deploy" silently breaks (it uninstalls+reinstalls with
# its own throwaway key with no warning). This target re-signs the local
# export with the same persistent key so it drops into the same install
# lineage as official builds: no uninstall needed, and future real updates
# would apply to it too.
#
# Needs the signing secrets locally, OUTSIDE this repo (never commit them,
# never point export_presets.cfg's tracked keystore/debug fields at them):
#   $(ODISEA_SIGNING_DIR)/odisea-update.jks
#   $(ODISEA_SIGNING_DIR)/github-secrets.txt with lines
#     ANDROID_KEYSTORE_PASSWORD=... / ANDROID_KEY_ALIAS=... / ANDROID_KEY_PASSWORD=...
# (whoever holds ANDROID_KEYSTORE_BASE64 from the GitHub secret can regenerate
# this locally; see the comment in that file for the base64 command.)
ODISEA_SIGNING_DIR ?= $(HOME)/.config/odisea-signing
ANDROID_UPDATE_KEYSTORE ?= $(ODISEA_SIGNING_DIR)/odisea-update.jks
ANDROID_SIGNING_SECRETS ?= $(ODISEA_SIGNING_DIR)/github-secrets.txt
ANDROID_BUILD_TOOLS := $(shell find "$$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n1)
ANDROID_TEST_APK ?= build/android/odisea_localtest.apk
# versionCode BAJO a proposito. En Android el update baja un APK y se lo pasa al
# instalador del sistema, asi que el versionCode es una barrera dura: con el 900000
# que habia antes, cualquier nightly real (versionCode = github.run_number, hoy ~348)
# era un DOWNGRADE y el sistema lo rechazaba — el juego ofrecia la actualizacion y la
# instalacion fallaba. Con 1, todo nightly es un upgrade y entra limpio.
# Para volver de un nightly a un build local hace falta el -d de adb install (permitido
# porque el APK es --export-debug); ya esta en el target android-install.
ANDROID_TEST_VERSION_CODE ?= 1
# Canal que va a consultar el update: es el unico que se publica hoy.
ANDROID_TEST_CHANNEL ?= nightly
ANDROID_PACKAGE ?= org.odisea.game

android-debug-signed:
	@[ -f "$(ANDROID_UPDATE_KEYSTORE)" ] || (echo "ERROR: no existe $(ANDROID_UPDATE_KEYSTORE) — hace falta la llave de firma real, no la generes de nuevo" && exit 1)
	@[ -f "$(ANDROID_SIGNING_SECRETS)" ] || (echo "ERROR: falta $(ANDROID_SIGNING_SECRETS)" && exit 1)
	@[ -n "$(ANDROID_BUILD_TOOLS)" ] || (echo "ERROR: no encontre build-tools bajo \$$ANDROID_HOME ($$ANDROID_HOME)" && exit 1)
	@mkdir -p build/android
	@set -e; \
	cp export_presets.cfg /tmp/odisea_export_presets.cfg.bak; \
	trap 'mv /tmp/odisea_export_presets.cfg.bak export_presets.cfg; rm -f build_meta.json' EXIT; \
	sed -i -E 's|^version/code = .*|version/code = $(ANDROID_TEST_VERSION_CODE)|' export_presets.cfg; \
	sed -i -E 's|^version/name = .*|version/name = "0.0.0-localtest.$(ANDROID_TEST_VERSION_CODE)"|' export_presets.cfg; \
	python3 scripts/inject_build_meta.py \
		--commit "$$(git rev-parse --short HEAD 2>/dev/null || echo local)" \
		--build-id "$(ANDROID_TEST_VERSION_CODE)" \
		--channel "$(ANDROID_TEST_CHANNEL)" \
		--version "0.0.0-localtest.$(ANDROID_TEST_VERSION_CODE)" \
		--official-host "odisea.educa.juegos" \
		--out-json "build_meta.json"; \
	$(GODOT) --editor --quit --headless >/dev/null 2>&1 || true; \
	$(GODOT) --no-window --export-debug "Android" "$(ANDROID_TEST_APK)" --headless; \
	test -s "$(ANDROID_TEST_APK)" || (echo "ERROR: export no produjo $(ANDROID_TEST_APK)" && exit 1)
	@set -e; \
	eval "$$(grep -E '^[A-Z_][A-Z0-9_]*=' "$(ANDROID_SIGNING_SECRETS)")"; \
	UNSIGNED="$(ANDROID_TEST_APK).unsigned"; ALIGNED="$(ANDROID_TEST_APK).aligned"; \
	mv "$(ANDROID_TEST_APK)" "$$UNSIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/zipalign" -p -f 4 "$$UNSIGNED" "$$ALIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/apksigner" sign --ks "$(ANDROID_UPDATE_KEYSTORE)" --ks-key-alias "$$ANDROID_KEY_ALIAS" --ks-pass "pass:$$ANDROID_KEYSTORE_PASSWORD" --key-pass "pass:$$ANDROID_KEY_PASSWORD" --out "$(ANDROID_TEST_APK)" "$$ALIGNED"; \
	rm -f "$$UNSIGNED" "$$ALIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/apksigner" verify "$(ANDROID_TEST_APK)"
	@$(MAKE) --no-print-directory android-clean-asset-copies
	@echo "OK: $(ANDROID_TEST_APK) firmado con la llave de produccion (misma identidad que los nightlies oficiales)."

# El custom build de Android deja DOS copias completas del proyecto adentro del propio
# proyecto: android/build/assets (salida del export de Godot) y su clon en
# android/build/build/intermediates/assets (mergeDebugAssets de Gradle). Cada .gd con
# class_name queda triplicado y el editor escupe "Unique global class X already exists"
# al abrir. El .gdignore de android/build/ alcanza para el filesystem del editor, pero NO
# para el language server de GDScript (3.6): ese recorre todos los .gd de res:// con un
# walk propio que no consulta .gdignore, y por eso los errores aparecen recien cuando se
# conecta el cliente LSP. Con el APK ya firmado las copias no sirven para nada y se
# regeneran solas en el proximo build, asi que se borran. Se conserva el resto del cache
# de Gradle (dex, java compilado) para no perder incrementalidad: solo se rehace el merge
# de assets.
android-clean-asset-copies:
	@rm -rf android/build/assets android/build/build/intermediates/assets
	@echo "OK: limpiadas las copias duplicadas del proyecto bajo android/build/."

# -d permite bajar de versionCode: hace falta para reinstalar el build local (code 1)
# encima de un nightly (code ~348) sin desinstalar. Android solo lo acepta en APKs
# debuggables, que es lo que produce --export-debug.
android-install: android-debug-signed
	adb install -r -d "$(ANDROID_TEST_APK)"
	adb shell am start -n $(ANDROID_PACKAGE)/com.godot.game.GodotApp

# Build RELEASE (no --export-debug) para descartar overhead de debug build como causa
# de un problema de performance. Mismo flujo de firma que android-debug-signed, pero
# un APK release NO es debuggable: adb install -d (downgrade) no funciona sobre el, asi
# que usa un versionCode mas alto que cualquier nightly real para instalar sin -d.
ANDROID_RELEASE_APK ?= build/android/odisea_release.apk
ANDROID_RELEASE_VERSION_CODE ?= 999999999

android-release-signed:
	@[ -f "$(ANDROID_UPDATE_KEYSTORE)" ] || (echo "ERROR: no existe $(ANDROID_UPDATE_KEYSTORE) — hace falta la llave de firma real, no la generes de nuevo" && exit 1)
	@[ -f "$(ANDROID_SIGNING_SECRETS)" ] || (echo "ERROR: falta $(ANDROID_SIGNING_SECRETS)" && exit 1)
	@[ -n "$(ANDROID_BUILD_TOOLS)" ] || (echo "ERROR: no encontre build-tools bajo \$$ANDROID_HOME ($$ANDROID_HOME)" && exit 1)
	@mkdir -p build/android
	@set -e; \
	cp export_presets.cfg /tmp/odisea_export_presets_release.cfg.bak; \
	trap 'mv /tmp/odisea_export_presets_release.cfg.bak export_presets.cfg; rm -f build_meta.json' EXIT; \
	sed -i -E 's|^version/code = .*|version/code = $(ANDROID_RELEASE_VERSION_CODE)|' export_presets.cfg; \
	sed -i -E 's|^version/name = .*|version/name = "0.0.0-releasetest.$(ANDROID_RELEASE_VERSION_CODE)"|' export_presets.cfg; \
	sed -i -E 's|^keystore/release = .*|keystore/release = "res://android/debug.keystore"|' export_presets.cfg; \
	sed -i -E 's|^keystore/release_user = .*|keystore/release_user = "androiddebugkey"|' export_presets.cfg; \
	sed -i -E 's|^keystore/release_password = .*|keystore/release_password = "android"|' export_presets.cfg; \
	python3 scripts/inject_build_meta.py \
		--commit "$$(git rev-parse --short HEAD 2>/dev/null || echo local)" \
		--build-id "$(ANDROID_RELEASE_VERSION_CODE)" \
		--channel "$(ANDROID_TEST_CHANNEL)" \
		--version "0.0.0-releasetest.$(ANDROID_RELEASE_VERSION_CODE)" \
		--official-host "odisea.educa.juegos" \
		--out-json "build_meta.json"; \
	$(GODOT) --editor --quit --headless >/dev/null 2>&1 || true; \
	$(GODOT) --no-window --export "Android" "$(ANDROID_RELEASE_APK)" --headless; \
	test -s "$(ANDROID_RELEASE_APK)" || (echo "ERROR: export no produjo $(ANDROID_RELEASE_APK)" && exit 1)
	@set -e; \
	eval "$$(grep -E '^[A-Z_][A-Z0-9_]*=' "$(ANDROID_SIGNING_SECRETS)")"; \
	UNSIGNED="$(ANDROID_RELEASE_APK).unsigned"; ALIGNED="$(ANDROID_RELEASE_APK).aligned"; \
	mv "$(ANDROID_RELEASE_APK)" "$$UNSIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/zipalign" -p -f 4 "$$UNSIGNED" "$$ALIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/apksigner" sign --ks "$(ANDROID_UPDATE_KEYSTORE)" --ks-key-alias "$$ANDROID_KEY_ALIAS" --ks-pass "pass:$$ANDROID_KEYSTORE_PASSWORD" --key-pass "pass:$$ANDROID_KEY_PASSWORD" --out "$(ANDROID_RELEASE_APK)" "$$ALIGNED"; \
	rm -f "$$UNSIGNED" "$$ALIGNED"; \
	"$(ANDROID_BUILD_TOOLS)/apksigner" verify "$(ANDROID_RELEASE_APK)"
	@$(MAKE) --no-print-directory android-clean-asset-copies
	@echo "OK: $(ANDROID_RELEASE_APK) firmado con la llave de produccion (build RELEASE, no debug)."

# Sin -d: un APK release no es debuggable, asi que el versionCode alto (999999999)
# alcanza para pasar por encima de cualquier nightly sin necesitarlo.
android-install-release: android-release-signed
	adb install -r "$(ANDROID_RELEASE_APK)"
	adb shell am start -n $(ANDROID_PACKAGE)/com.godot.game.GodotApp

.PHONY: all bake bake-dome-geometry bake-lightmap-postprocess reimport-split-stream-meshes export-linux-arm64 export-pck export export-web-threads deploy-netlify web dashboard-dev-central deploy-dashboard android-debug-signed android-install android-clean-asset-copies android-release-signed android-install-release
