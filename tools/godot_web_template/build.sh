#!/usr/bin/env bash
# Compila la plantilla de exportacion HTML5 (con hilos, release) con el unico cambio que
# necesitamos sobre Godot 3.6.2: el padding del UBO de la luz direccional.
#
# Por que hace falta: docs/agents/web_gles3_directional_light.md
#
#   ./tools/godot_web_template/build.sh [directorio_de_trabajo]
#
# Deja el .zip listo para subir como asset de release y para copiar sobre
# ~/.local/share/godot/templates/3.6.2.stable/webassembly_threads_release.zip
set -euo pipefail

TAG="3.6.2-stable"
EMSDK_VERSION="3.1.39"       # la que uso Godot para las plantillas 3.6 oficiales
TRABAJO="${1:-$HOME/src}"
PARCHE="$(cd "$(dirname "$0")" && pwd)/scene_glsl_directional_ubo.patch"

mkdir -p "$TRABAJO"
cd "$TRABAJO"

if [ ! -d emsdk ]; then
	git clone --depth 1 https://github.com/emscripten-core/emsdk.git
fi
(cd emsdk && ./emsdk install "$EMSDK_VERSION" && ./emsdk activate "$EMSDK_VERSION")

if [ ! -d godot36 ]; then
	git clone --depth 1 --branch "$TAG" https://github.com/godotengine/godot.git godot36
fi
cd godot36
git checkout -- drivers/gles3/shaders/scene.glsl 2>/dev/null || true
git apply "$PARCHE"
git --no-pager diff --stat

# shellcheck disable=SC1091
source "$TRABAJO/emsdk/emsdk_env.sh"
scons platform=javascript tools=no target=release threads_enabled=yes javascript_eval=yes \
	-j"$(nproc)"

echo
echo "Plantilla lista: $TRABAJO/godot36/bin/godot.javascript.opt.threads.zip"
echo "Instalar en local:"
echo "  cp \$_ ~/.local/share/godot/templates/3.6.2.stable/webassembly_threads_release.zip"
