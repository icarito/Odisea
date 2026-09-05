#!/usr/bin/env bash
# Compila las librerias del motor Godot 3.6.2 para Android (AAR de custom build)
# con el parche que hace DirAccessJAndroid::make_dir_recursive idempotente.
#
# Por que hace falta: docs/agents/android_shader_cache.md
#
#   ./tools/godot_android_template/build.sh [directorio_de_trabajo]
#
# Deja el godot-lib.debug.aar listo para copiar dentro de
# ~/.local/share/godot/templates/3.6.2.stable/android_source.zip (path
# libs/debug/godot-lib.debug.aar) o para usar como
# android/build/libs/debug/godot-lib.debug.aar del proyecto.
set -euo pipefail

TAG="3.6.2-stable"
TRABAJO="${1:-$HOME/src}"
PARCHE="$(cd "$(dirname "$0")" && pwd)/dir_access_jandroid_make_dir_recursive_idempotent.patch"

mkdir -p "$TRABAJO"
cd "$TRABAJO"

if [ ! -d godot36 ]; then
	git clone --depth 1 --branch "$TAG" https://github.com/godotengine/godot.git godot36
fi
cd godot36
# Arbol limpio salvo el parche: el tree puede tener restos del build web (scene.glsl)
git checkout -- . 2>/dev/null || true
git apply --check "$PARCHE"
git apply "$PARCHE"
git --no-pager diff --stat

scons platform=android target=release_debug android_arch=arm64v8 -j"$(nproc)"
# El APK de debug de este proyecto es arm64-only (lib/arm64-v8a). Si alguna vez
# se agrega armv7 al preset, correr tambien:
#   scons platform=android target=release_debug android_arch=armv7 -j"$(nproc)"

cd platform/android/java
# El gradle del motor exige JAVA 17 y que ANDROID_HOME == ANDROID_SDK_ROOT.
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
./gradlew :lib:assembleTemplateDebug

AAR="$TRABAJO/godot36/platform/android/java/lib/build/outputs/aar/godot-lib.debug.aar"
echo
echo "AAR listo: $AAR"
echo "Instalar en el template local:"
echo "  cd /tmp && rm -rf android_src_patched && mkdir android_src_patched && unzip -q ~/.local/share/godot/templates/3.6.2.stable/android_source.zip -d android_src_patched"
echo "  cp \"\$AAR\" android_src_patched/libs/debug/godot-lib.debug.aar"
echo "  (cd android_src_patched && zip -q ~/.local/share/godot/templates/3.6.2.stable/android_source.zip libs/debug/godot-lib.debug.aar)"
