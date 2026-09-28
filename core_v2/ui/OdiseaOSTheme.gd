extends Reference

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

# --- URGENCIA: cuanto me necesita ahora (FD-319) ---------------------------------
# Canal ORTOGONAL a la identidad (Manual §6). El color del sistema NUNCA cambia por
# urgencia: la identidad la dicen state()/accent_for() y no se toca. La urgencia se
# expresa con borde, pulso, badge y brillo, asi que estos tokens son SOLO presentacion
# (numeros y booleanos), no colores. El borde y el badge se tinen con accent_for(screen_id),
# que es identidad; por eso no hay ningun Color aca: no se duplican los tokens de arriba.
const URGENCY_QUIET := "quiet"
const URGENCY_NOTICE := "notice"
const URGENCY_URGENT := "urgent"
const URGENCY_ALARM := "alarm"

# Orden creciente: el indice ES el nivel. Una sola fuente de verdad, sin "level" duplicado
# dentro del token.
const URGENCY_ORDER := [URGENCY_QUIET, URGENCY_NOTICE, URGENCY_URGENT, URGENCY_ALARM]

# Token de presentacion por nivel:
#   pulse_hz        ciclos por segundo del pulso (0 = sin pulso; presentacion, no estado)
#   pulse_min_alpha alpha minimo del pulso (1.0 = no baja)
#   border_alpha    opacidad del borde (0 = sin borde)
#   badge           si el nivel pide badge
#   glow            intensidad de brillo, para el render que lo soporte
const URGENCY_BY_NAME := {
	URGENCY_QUIET: {"pulse_hz": 0.0, "pulse_min_alpha": 1.0, "border_alpha": 0.0, "badge": false, "glow": 0.0},
	URGENCY_NOTICE: {"pulse_hz": 0.0, "pulse_min_alpha": 1.0, "border_alpha": 0.55, "badge": false, "glow": 0.15},
	URGENCY_URGENT: {"pulse_hz": 0.4, "pulse_min_alpha": 0.55, "border_alpha": 0.9, "badge": false, "glow": 0.35},
	URGENCY_ALARM: {"pulse_hz": 1.0, "pulse_min_alpha": 0.35, "border_alpha": 1.0, "badge": true, "glow": 0.6},
}

# Nivel numerico de un nombre (quiet = 0). Un nombre desconocido se lee como quiet, que es
# la verdad: no hay urgencia declarada.
static func urgency_level(name: String) -> int:
	var index: int = URGENCY_ORDER.find(name.to_lower())
	return index if index >= 0 else 0

# Nombre canonico de un nivel. Un nombre desconocido cae a quiet.
static func normalize_urgency(name: String) -> String:
	return URGENCY_ORDER[urgency_level(name)]

# Token de presentacion del nivel (nunca un color). Un nombre desconocido cae a quiet.
static func urgency_token(name: String) -> Dictionary:
	return URGENCY_BY_NAME[normalize_urgency(name)]

# Regla de asignacion de FD-319, funcion pura y determinista:
#   - base   = default_urgency del prop (piso; nunca se baja de ahi)
#   - context_level = lo que pide el contexto (puede elevar)
#   - previous = ultimo nivel resuelto (para limitar el cambio por tick)
# Devuelve el nombre del nivel resultante. Sube como maximo UN nivel por evaluacion, pero
# puede bajar de inmediato al pedido del contexto (siempre por encima o igual a la base).
# previous vacio significa "primera evaluacion": se arranca en la base y se sube un escalon.
static func resolve_urgency(base: String, context_level: String, previous: String) -> String:
	var floor_level: int = urgency_level(base)
	var target: int = int(max(floor_level, urgency_level(context_level)))
	var start: int = urgency_level(previous)
	if start < floor_level:
		start = floor_level
	return URGENCY_ORDER[int(min(target, start + 1))]

# Alpha del pulso para el nivel en un instante (elapsed en segundos). Presentacion pura:
# interpola la lectura para que el widget la dibuje; no decide estado. Sin pulso devuelve 1.0.
static func urgency_pulse_alpha(name: String, elapsed: float) -> float:
	var token := urgency_token(name)
	var hz := float(token.get("pulse_hz", 0.0))
	if hz <= 0.0:
		return 1.0
	var low := float(token.get("pulse_min_alpha", 1.0))
	var phase := 0.5 + 0.5 * sin(elapsed * hz * PI * 2.0)
	return lerp(low, 1.0, phase)
