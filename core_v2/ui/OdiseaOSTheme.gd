extends Reference
class_name OdiseaOSTheme

# OdiseaOSTheme.gd - El lenguaje visual de OdiseaOS, en un solo lugar.
#
# Spec: docs/odiseaos/MANUAL_DEL_TRIPULANTE.md §2 (las dos superficies) y §6 (codigo de
# color). Si un color de la GUI no sale de aca, o es un token que falta o es un error.
#
# Por que existe: la medicion del 2026-09-20 encontro 47 colores distintos escritos a
# mano en core_v2/ui/hud/ (140 ocurrencias sumando radial y a bordo), con el gris de
# OFFLINE copiado 11 veces, el mismo cian como 0.83 y como 0.835, y el rojo de alarma
# con dos opacidades. Estos ~15 tokens los reemplazan.
#
# Es un Reference con constantes, no un Theme .tres: lo que la GUI necesita hoy son
# valores que el codigo lee al pintar (draw_*, ColorRect.color, add_color_override), no
# StyleBoxes de control. Si algun dia hace falta un .tres, se arma desde estos tokens.

# --- ORIGEN: de quien es la pantalla (Manual §2) ---------------------------------
# Cian = el traje. Viaja con usted.
const SUIT_ACCENT := Color(0.0, 0.835, 1.0, 1.0)        # #00D5FF
const SUIT_DIM := Color(0.42, 0.68, 0.76, 1.0)          # texto y bordes en reposo
# Verde fosforo = a bordo. Se queda donde esta.
const SHIP_ACCENT := Color(0.607843, 0.992157, 0.580392, 1.0)   # #9BFD94 (el verde real de RetroOS.tres)
# Ambar = atencion de a bordo, y el rechazo (Manual §6: "amber nunca es averia").
const SHIP_ALT := Color(0.878431, 0.686275, 0.254902, 1.0)      # #E0AF41
const DENY := Color(1.0, 0.72, 0.23, 1.0)               # destello de "no se puede"

# --- ESTADO: que pasa (Manual §6) ------------------------------------------------
const STATE_NOMINAL := Color(0.1, 0.9, 0.4, 0.9)        # verde: nada que hacer
const STATE_ACTIVE := Color(0.18, 0.88, 0.78, 0.9)      # turquesa: algo suyo esta encendido
const STATE_CAUTION := Color(0.9, 0.8, 0.2, 0.9)        # ambar: anotelo
const STATE_ALARM := Color(0.9, 0.3, 0.2, 0.9)          # rojo: es su problema
const STATE_OFFLINE := Color(0.5, 0.5, 0.5, 0.8)        # gris: sin lectura, no es falla

# --- SUPERFICIE ------------------------------------------------------------------
const SURFACE_GLASS := Color(0.0, 0.05, 0.08, 0.55)     # fondo translucido (dial, cajon)
const SURFACE_PANEL := Color(0.05, 0.08, 0.1, 1.0)      # fondo de widget
const SURFACE_BORDER := Color(0.24, 0.55, 0.65, 1.0)    # marco de slot
const SURFACE_HOT := Color(0.0, 0.55, 0.7, 0.4)         # fila/sector bajo el cursor
const INK := Color(0.85, 0.95, 1.0, 1.0)                # texto sobre panel

# Un estado por nombre, para los widgets que traen el estado en el snapshot.
const STATE_BY_NAME := {
	"nominal": STATE_NOMINAL,
	"ok": STATE_NOMINAL,
	"active": STATE_ACTIVE,
	"caution": STATE_CAUTION,
	"degraded": STATE_CAUTION,
	"alarm": STATE_ALARM,
	"fault": STATE_ALARM,
	"offline": STATE_OFFLINE,
}

# Devuelve el color de estado, o STATE_OFFLINE si el nombre no esta en el vocabulario.
# No inventa colores: un estado desconocido se lee como "sin lectura", que es la verdad.
static func state(name: String) -> Color:
	var key := name.to_lower()
	if STATE_BY_NAME.has(key):
		return STATE_BY_NAME[key]
	return STATE_OFFLINE

# El acento segun de quien es la pantalla. `screen_id` usa el prefijo antes de ":".
# "player:*" y "suit:*" son del traje; todo lo demas (ship:, drone:, holoterminal:) es
# de a bordo.
static func accent_for(screen_id: String) -> Color:
	var prefix := screen_id.split(":")[0] if screen_id.find(":") >= 0 else ""
	if prefix == "player" or prefix == "suit":
		return SUIT_ACCENT
	return SHIP_ACCENT
