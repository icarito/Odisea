#!/usr/bin/env sh
# Tintado post-bake idempotente. El sello guarda el hash de la salida, para no
# teñir/oscurecer de nuevo el PNG cuando make bake se ejecuta sin un recocido.
set -eu

LIGHTMAP_PATH="${DOME_LIGHTMAP_PATH:-core_v2/levels/interiors/TerraceMesh.png}"
TINT="${DOME_LIGHTMAP_TINT:-008da3}"
COLORIZE="${DOME_LIGHTMAP_COLORIZE:-85}"
BRIGHTNESS="${DOME_LIGHTMAP_BRIGHTNESS:-15}"
STAMP_DIR="${DOME_LIGHTMAP_STAMP_DIR:-build/lightmap-postprocess}"
STAMP_PATH="${STAMP_DIR}/$(basename "${LIGHTMAP_PATH}").sha256"

case "${TINT}" in
	\#*) ;;
	*) TINT="#${TINT}" ;;
esac

if ! command -v magick >/dev/null 2>&1; then
	echo "[dome_lightmap_post] ERROR: ImageMagick 7 ('magick') no esta instalado." >&2
	exit 1
fi
if [ ! -f "${LIGHTMAP_PATH}" ]; then
	echo "[dome_lightmap_post] ERROR: no existe ${LIGHTMAP_PATH}" >&2
	exit 1
fi

mkdir -p "${STAMP_DIR}"
CURRENT_HASH="$(sha256sum "${LIGHTMAP_PATH}" | awk '{print $1}')"
if [ -f "${STAMP_PATH}" ] && [ "${CURRENT_HASH}" = "$(tr -d '[:space:]' < "${STAMP_PATH}")" ]; then
	echo "[dome_lightmap_post] sin cambios crudos; se conserva ${LIGHTMAP_PATH}"
	exit 0
fi

TEMP_PATH="$(mktemp "${LIGHTMAP_PATH}.postprocess.XXXXXX")"
trap 'rm -f "${TEMP_PATH}"' EXIT HUP INT TERM
magick "${LIGHTMAP_PATH}" \
	-fill "${TINT}" -colorize "${COLORIZE}%" \
	-modulate "${BRIGHTNESS},100,100" \
	"${TEMP_PATH}"
mv -f "${TEMP_PATH}" "${LIGHTMAP_PATH}"
trap - EXIT HUP INT TERM
sha256sum "${LIGHTMAP_PATH}" | awk '{print $1}' > "${STAMP_PATH}"
echo "[dome_lightmap_post] PASS. tint=${TINT} colorize=${COLORIZE}% brightness=${BRIGHTNESS}% -> ${LIGHTMAP_PATH}"
