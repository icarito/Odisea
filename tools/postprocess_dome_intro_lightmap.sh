#!/usr/bin/env sh
# Tintado post-bake idempotente. El sello guarda el hash de la salida, para no
# teñir/oscurecer de nuevo el PNG cuando make bake se ejecuta sin un recocido.
set -eu

LIGHTMAP_PATH="${DOME_LIGHTMAP_PATH:-}"
LIGHTMAP_DATA_PATH="${DOME_LIGHTMAP_DATA_PATH:-core_v2/levels/interiors/Dome_Intro.lmbake}"
TINT="${DOME_LIGHTMAP_TINT:-008da3}"
COLORIZE="${DOME_LIGHTMAP_COLORIZE:-70}"
BRIGHTNESS="${DOME_LIGHTMAP_BRIGHTNESS:-24}"
# TerraceFloor necesita contraste para que la luz direccional y sus sombras
# sobrevivan el grading. El domo y los props conservan el look más intenso.
FLOOR_COLORIZE="${DOME_LIGHTMAP_FLOOR_COLORIZE:-28}"
FLOOR_BRIGHTNESS="${DOME_LIGHTMAP_FLOOR_BRIGHTNESS:-75}"
# Desenfoque gaussiano en pixeles del lightmap (0 = apagado). Suaviza el borde duro de
# las sombras horneadas, que a esta resolucion (muchos lightmaps son de 118 a 270 px)
# se ve escalonado. Se aplica ANTES del tinte para no arrastrar el color.
BLUR="${DOME_LIGHTMAP_BLUR:-2.5}"
# Contraste sigmoidal (0 = apagado). Sube los focos de los wall lights y hunde la
# penumbra, en vez de levantar todo por igual como hace BRIGHTNESS. Es la perilla
# para "que se note de donde viene la luz" sin volver a hornear: en el bake los
# fixtures YA son las zonas claras, asi que separarlas del fondo equivale a subirles
# la energia. Se aplica DESPUES del blur y ANTES del tinte, para no sesgar el color.
CONTRAST="${DOME_LIGHTMAP_CONTRAST:-0}"
# Punto medio del sigmoide, en %. Por debajo de 50 protege las sombras (sube solo los
# focos); por encima hunde mas la penumbra. Un lightmap oscuro quiere un medio bajo.
CONTRAST_MIDPOINT="${DOME_LIGHTMAP_CONTRAST_MIDPOINT:-40}"
# FD-284: el bake destino se elige con DOME_LIGHTMAP_DATA_PATH (por ejemplo
# core_v2/levels/interiors/lightmaps/dark/Dome_Intro.lmbake). Cada modo necesita SU
# propio STAMP_DIR y RAW_DIR: con atlas apagado los PNG por malla se llaman igual en
# los dos modos, asi que compartir carpeta haria que el sello de uno saltee el
# postproceso del otro y que la copia cruda de uno se procese como la del otro.
STAMP_DIR="${DOME_LIGHTMAP_STAMP_DIR:-build/lightmap-postprocess}"
FORCE="${DOME_LIGHTMAP_FORCE:-0}"
# Retocar el look sin volver a hornear. FORCE=1 significa "acabo de hornear": guarda la
# salida CRUDA en RAW_DIR y procesa desde ahi. RETUNE=1 vuelve a procesar desde esa
# copia cruda con otros parametros, sin re-hornear y sin apilar el tinte sobre si mismo,
# que es lo que obligaba a un bake completo para cambiar un numero.
RETUNE="${DOME_LIGHTMAP_RETUNE:-0}"
RAW_DIR="${DOME_LIGHTMAP_RAW_DIR:-build/lightmap-raw}"

case "${TINT}" in
	\#*) ;;
	*) TINT="#${TINT}" ;;
esac

if ! command -v magick >/dev/null 2>&1; then
	echo "[dome_lightmap_post] ERROR: ImageMagick 7 ('magick') no esta instalado." >&2
	exit 1
fi
mkdir -p "${STAMP_DIR}" "${RAW_DIR}"

# BakedLightmap genera una textura por MeshInstance cuando el atlas está
# desactivado. La lista se extrae del .lmbake recién creado, en vez de asumir que
# solo existe TerraceMesh.png. DOME_LIGHTMAP_PATH conserva un override puntual.
PATHS_FILE="$(mktemp)"
trap 'rm -f "${PATHS_FILE}"' EXIT HUP INT TERM
if [ -n "${LIGHTMAP_PATH}" ]; then
	printf '%s\n' "${LIGHTMAP_PATH}" > "${PATHS_FILE}"
elif [ -f "${LIGHTMAP_DATA_PATH}" ]; then
	# strings solo sirve si el .lmbake quedo SIN comprimir. Al recocer, Godot lo guarda
	# comprimido (firma RSCC) y la extraccion devolvia cero rutas, con lo cual el
	# postproceso abortaba justo despues de un bake, que es cuando mas se lo necesita.
	strings -a "${LIGHTMAP_DATA_PATH}" | sed -n 's#^res://\(.*\.png\)$#\1#p' > "${PATHS_FILE}"
	if [ ! -s "${PATHS_FILE}" ]; then
		echo "[dome_lightmap_post] .lmbake comprimido; pidiendo las rutas a Godot"
		"${GODOT_BIN:-godot3-bin}" --path . --no-window -s tools/dump_lightmap_paths.gd \
			-- "--data=res://${LIGHTMAP_DATA_PATH}" 2>/dev/null \
			| sed -n 's#^res://\(.*\.png\)$#\1#p' > "${PATHS_FILE}" || true
	fi
else
	echo "[dome_lightmap_post] ERROR: no existe ${LIGHTMAP_DATA_PATH}" >&2
	exit 1
fi

if [ ! -s "${PATHS_FILE}" ]; then
	echo "[dome_lightmap_post] ERROR: el lightmap no referencia PNGs para procesar." >&2
	exit 1
fi

# Contador de imagenes realmente procesadas. El bucle NO corre en subshell (la
# redireccion desde archivo no crea uno, a diferencia de un pipe), asi que sobrevive.
processed=0
while IFS= read -r image_path; do
	if [ ! -f "${image_path}" ]; then
		echo "[dome_lightmap_post] ERROR: no existe ${image_path}" >&2
		exit 1
	fi
	stamp_path="${STAMP_DIR}/$(basename "${image_path}").sha256"
	current_hash="$(sha256sum "${image_path}" | awk '{print $1}')"
	# El sello no aplica cuando se esta retocando el look: ahi la fuente es la copia
	# cruda, no la imagen actual, y justamente queremos reprocesarla con otros numeros.
	if [ "${RETUNE}" != "1" ] && [ -f "${stamp_path}" ] && [ "${current_hash}" = "$(tr -d '[:space:]' < "${stamp_path}")" ]; then
		echo "[dome_lightmap_post] sin cambios crudos; se conserva ${image_path}"
		continue
	fi
	# El PNG ya procesado se versiona. Sin una señal explícita de que BakedLightmap
	# acaba de sobrescribirlo, no se puede distinguir de una salida cruda en un clone
	# nuevo y aplicarle el look otra vez lo oscurece indebidamente.
	raw_path="${RAW_DIR}/$(basename "${image_path}")"
	if [ "${RETUNE}" = "1" ]; then
		if [ ! -f "${raw_path}" ]; then
			echo "[dome_lightmap_post] sin copia cruda de $(basename "${image_path}"); hornea una vez y vuelve a intentar" >&2
			continue
		fi
	elif [ "${FORCE}" = "1" ]; then
		# Recien horneado: esta imagen ES la salida cruda. Se guarda antes de tocarla.
		cp -f "${image_path}" "${raw_path}"
	else
		echo "[dome_lightmap_post] sin bake nuevo confirmado; se conserva ${image_path}"
		continue
	fi
	colorize="${COLORIZE}"
	brightness="${BRIGHTNESS}"
	if [ "$(basename "${image_path}")" = "TerraceFloor.png" ]; then
		colorize="${FLOOR_COLORIZE}"
		brightness="${FLOOR_BRIGHTNESS}"
	fi
	blur_args=""
	if [ "${BLUR}" != "0" ]; then
		blur_args="-blur 0x${BLUR}"
	fi
	contrast_args=""
	if [ "${CONTRAST}" != "0" ]; then
		contrast_args="-sigmoidal-contrast ${CONTRAST}x${CONTRAST_MIDPOINT}%"
	fi
	temp_path="$(mktemp "${image_path}.postprocess.XXXXXX")"
	# PNG24 es obligatorio: sin eso ImageMagick elige paleta para estas imagenes y los
	# lightmaps quedaban cuantizados (12 de 41 con solo 16 colores), lo que arruina
	# justamente el degradado que un lightmap tiene que aportar.
	magick "${raw_path}" \
		${blur_args} \
		${contrast_args} \
		-fill "${TINT}" -colorize "${colorize}%" \
		-modulate "${brightness},100,100" \
		-type TrueColor \
		-strip \
		"PNG24:${temp_path}"
	mv -f "${temp_path}" "${image_path}"
	processed=$((processed + 1))
	sha256sum "${image_path}" | awk '{print $1}' > "${stamp_path}"
	echo "[dome_lightmap_post] PASS. tint=${TINT} colorize=${colorize}% brightness=${brightness}% blur=${BLUR} contrast=${CONTRAST}x${CONTRAST_MIDPOINT}% -> ${image_path}"
done < "${PATHS_FILE}"

# Cambiar un numero del look y ver que "no pasa nada" es el error mas facil de cometer
# con este script: el sello conserva las imagenes salvo que se le diga explicitamente
# que se esta retocando. Antes salia en silencio con codigo 0.
if [ "${processed}" = "0" ] && [ "${RETUNE}" != "1" ] && [ "${FORCE}" != "1" ]; then
	echo "" >&2
	echo "[dome_lightmap_post] NO SE PROCESO NINGUNA IMAGEN." >&2
	echo "  Para cambiar el look sin re-hornear, usa:  make retune-lightmap DOME_LIGHTMAP_BRIGHTNESS=50" >&2
	echo "  (equivale a RETUNE=1 + el reimport de Godot, que tambien hace falta)" >&2
fi
