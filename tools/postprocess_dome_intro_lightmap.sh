#!/usr/bin/env sh
# Tintado post-bake idempotente. El sello guarda el hash de la salida, para no
# teñir/oscurecer de nuevo el PNG cuando make bake se ejecuta sin un recocido.
set -eu

LIGHTMAP_PATH="${DOME_LIGHTMAP_PATH:-}"
LIGHTMAP_DATA_PATH="${DOME_LIGHTMAP_DATA_PATH:-core_v2/levels/interiors/Dome_Intro.lmbake}"
TINT="${DOME_LIGHTMAP_TINT:-008da3}"
COLORIZE="${DOME_LIGHTMAP_COLORIZE:-85}"
BRIGHTNESS="${DOME_LIGHTMAP_BRIGHTNESS:-15}"
# TerraceFloor necesita contraste para que la luz direccional y sus sombras
# sobrevivan el grading. El domo y los props conservan el look más intenso.
FLOOR_COLORIZE="${DOME_LIGHTMAP_FLOOR_COLORIZE:-35}"
FLOOR_BRIGHTNESS="${DOME_LIGHTMAP_FLOOR_BRIGHTNESS:-65}"
STAMP_DIR="${DOME_LIGHTMAP_STAMP_DIR:-build/lightmap-postprocess}"
FORCE="${DOME_LIGHTMAP_FORCE:-0}"

case "${TINT}" in
	\#*) ;;
	*) TINT="#${TINT}" ;;
esac

if ! command -v magick >/dev/null 2>&1; then
	echo "[dome_lightmap_post] ERROR: ImageMagick 7 ('magick') no esta instalado." >&2
	exit 1
fi
mkdir -p "${STAMP_DIR}"

# BakedLightmap genera una textura por MeshInstance cuando el atlas está
# desactivado. La lista se extrae del .lmbake recién creado, en vez de asumir que
# solo existe TerraceMesh.png. DOME_LIGHTMAP_PATH conserva un override puntual.
PATHS_FILE="$(mktemp)"
trap 'rm -f "${PATHS_FILE}"' EXIT HUP INT TERM
if [ -n "${LIGHTMAP_PATH}" ]; then
	printf '%s\n' "${LIGHTMAP_PATH}" > "${PATHS_FILE}"
elif [ -f "${LIGHTMAP_DATA_PATH}" ]; then
	strings -a "${LIGHTMAP_DATA_PATH}" | sed -n 's#^res://\(.*\.png\)$#\1#p' > "${PATHS_FILE}"
else
	echo "[dome_lightmap_post] ERROR: no existe ${LIGHTMAP_DATA_PATH}" >&2
	exit 1
fi

if [ ! -s "${PATHS_FILE}" ]; then
	echo "[dome_lightmap_post] ERROR: el lightmap no referencia PNGs para procesar." >&2
	exit 1
fi

while IFS= read -r image_path; do
	if [ ! -f "${image_path}" ]; then
		echo "[dome_lightmap_post] ERROR: no existe ${image_path}" >&2
		exit 1
	fi
	stamp_path="${STAMP_DIR}/$(basename "${image_path}").sha256"
	current_hash="$(sha256sum "${image_path}" | awk '{print $1}')"
	if [ -f "${stamp_path}" ] && [ "${current_hash}" = "$(tr -d '[:space:]' < "${stamp_path}")" ]; then
		echo "[dome_lightmap_post] sin cambios crudos; se conserva ${image_path}"
		continue
	fi
	# El PNG ya procesado se versiona. Sin una señal explícita de que BakedLightmap
	# acaba de sobrescribirlo, no se puede distinguir de una salida cruda en un clone
	# nuevo y aplicarle el look otra vez lo oscurece indebidamente.
	if [ "${FORCE}" != "1" ]; then
		echo "[dome_lightmap_post] sin bake nuevo confirmado; se conserva ${image_path}"
		continue
	fi
	colorize="${COLORIZE}"
	brightness="${BRIGHTNESS}"
	if [ "$(basename "${image_path}")" = "TerraceFloor.png" ]; then
		colorize="${FLOOR_COLORIZE}"
		brightness="${FLOOR_BRIGHTNESS}"
	fi
	temp_path="$(mktemp "${image_path}.postprocess.XXXXXX")"
	magick "${image_path}" \
		-fill "${TINT}" -colorize "${colorize}%" \
		-modulate "${brightness},100,100" \
		"${temp_path}"
	mv -f "${temp_path}" "${image_path}"
	sha256sum "${image_path}" | awk '{print $1}' > "${stamp_path}"
	echo "[dome_lightmap_post] PASS. tint=${TINT} colorize=${colorize}% brightness=${brightness}% -> ${image_path}"
done < "${PATHS_FILE}"
