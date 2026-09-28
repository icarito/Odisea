extends PanelContainer

# HudWidget.gd - Base comun de los widgets de slot de OdiseaOS.
#
# Spec: docs/odiseaos/MANUAL_DEL_TRIPULANTE.md §3.2 ("un widget no piensa: muestra la
# ultima lectura y nada mas"), §6 (codigo de color) y §7 (OFFLINE no es un error).
#
# Existe porque los widgets repetian ~15-20 lineas identicas cada uno: el
# update_snapshot -> set_snapshot de dos lineas, el mismo onready con el mismo path,
# la misma rama offline, y el mismo _ready() con guard de is_connected.
#
# CONTRATO CON EL HOST -- no cambia: SuitOSWidgetHost llama `update_snapshot(Dictionary)`
# y nada mas (ver SuitOSWidgetHost._on_widget_changed). La lectura sigue siendo data pura
# serializable. Un nodo adentro rompe el terminal auxiliar (Manual §8).
#
# COMO SE ESCRIBE UN WIDGET NUEVO
#   extends "res://core_v2/ui/hud/HudWidget.gd"
#   class_name MiWidget   # solo si ya estaba registrado
#   onready var _algo: Label = get_node_or_null("Margin/VBox/Algo")
#   func default_title() -> String: return tr("Mi pantalla")
#   func _render(snapshot: Dictionary) -> void:   # hay lectura
#       _set_dot(OdiseaOSTheme.STATE_NOMINAL)
#       _algo.text = String(snapshot.get("algo", ""))
#   func _render_offline() -> void:               # no hay lectura; el punto ya esta gris
#       _algo.text = tr("--")
#
# NO sobrescriba update_snapshot() ni set_snapshot(): sobrescriba _render/_render_offline.

const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
# Sin class_name a proposito: en Godot 3 registrar uno exige que el editor reescriba
# project.godot. Los hijos hacen `extends "res://core_v2/ui/hud/HudWidget.gd"` y heredan
# esta constante, asi que OdiseaOSTheme queda disponible en todos sin repetir el preload.
const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

# Los tres nodos que comparten todos los widgets con escena. get_node_or_null: un widget
# puede no tener cabecera (CryoPodWidget dibuja la suya) y eso no es un error.
onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")

# La identidad de la pantalla que este widget esta mostrando. Sale de la lectura, asi que
# el mismo widget sirve para varias instancias de la misma clase de pantalla.
var _screen_id: String = ""

# --- URGENCIA (canal ortogonal al color, FD-319) ---------------------------------
# Contrato del snapshot, ademas de lo de arriba:
#   "urgency"          String  nivel pedido: quiet|notice|urgent|alarm (default quiet).
#   "default_urgency"  String  base declarada por el prop. Si viaja, es el piso y "urgency"
#                              se lee como contexto que puede elevar (OdiseaOSTheme.resolve_urgency).
#                              Si no viaja, se pinta "urgency" tal cual (sin rampa).
# Presentacion: borde/pulso/badge salen de OdiseaOSTheme.urgency_token(nivel); NUNCA cambian
# el color de identidad. El pulso es interpolacion de presentacion desde la lectura, no estado.
# API para los hijos (la usa ProtocolWidget, FD-319 T4):
#   urgency() -> String                  nivel resuelto que se esta pintando
#   urgency_token() -> Dictionary        token de presentacion del nivel
#   urgency_pulse_alpha(elapsed) -> float  alpha del pulso en ese instante (1.0 = sin pulso)
var _urgency: String = OdiseaOSTheme.URGENCY_QUIET
var _urgency_clock: float = 0.0
# Badge opcional: solo los widgets que lo declaran en su escena lo ven; si falta, no es error.
onready var _urgency_badge: Label = get_node_or_null("Margin/VBox/Header/UrgencyBadge")

# Punto de entrada del host. Se mantiene por compatibilidad: el host prueba
# update_snapshot primero y set_snapshot despues.
func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	_screen_id = String(snapshot.get("id", _screen_id))
	if _screen_id.empty():
		_screen_id = default_screen_id()
	if _title_label != null:
		# Sin tr() a proposito: en Godot 3 Label.set_text ya pasa por el TranslationServer
		# al dibujar (es de lo que vive el retrofit de i18n, FD-303 §17). Un tr() explicito
		# aca traduciria dos veces. Los titulos viajan en espaniol dentro de la lectura y se
		# traducen en el dispositivo que dibuja, que es lo que necesita el terminal auxiliar
		# cuando esta en otro idioma que el host (Manual §8).
		_title_label.text = String(snapshot.get("title", default_title()))
	if is_offline(snapshot):
		_set_dot(OdiseaOSTheme.STATE_OFFLINE)
		# Offline es "sin lectura" (Manual §7): no hay urgencia viva que pintar.
		_update_urgency({})
		_render_offline()
		return
	_update_urgency(snapshot)
	_render(snapshot)

# --- a implementar por cada widget -----------------------------------------------

# Lo que dice la cabecera cuando la lectura no trae titulo.
func default_title() -> String:
	return tr("Pantalla")

# La identidad a usar si la lectura no trae "id". HUDableComponent siempre la inyecta,
# asi que esto solo cubre widgets alimentados a mano (tests, previews).
func default_screen_id() -> String:
	return ""

# Hay lectura. Pinte.
func _render(_snapshot: Dictionary) -> void:
	pass

# No hay lectura (Manual §7). El punto de estado ya quedo gris; deje el resto en un
# estado que se lea como "sin dato", no como cero.
func _render_offline() -> void:
	pass

# --- helpers ---------------------------------------------------------------------

static func is_offline(snapshot: Dictionary) -> bool:
	return String(snapshot.get("source", "online")) == "offline"

func _set_dot(color: Color) -> void:
	if _status_dot != null:
		_status_dot.color = color

# --- urgencia (FD-319) -----------------------------------------------------------

func urgency() -> String:
	return _urgency

func urgency_token() -> Dictionary:
	return OdiseaOSTheme.urgency_token(_urgency)

# Fase del pulso en un instante. Delega en el tema para que el render ImGui use la misma
# curva y el mismo token; el widget solo la consume.
func urgency_pulse_alpha(elapsed: float) -> float:
	return OdiseaOSTheme.urgency_pulse_alpha(_urgency, elapsed)

# Resuelve el nivel desde el snapshot y aplica su presentacion. Con "default_urgency" la
# regla del tema (base + elevacion, maximo un nivel por tick) decide; sin ella, manda
# "urgency" tal cual. previous es el ultimo nivel pintado por este widget.
func _update_urgency(snapshot: Dictionary) -> void:
	var requested := String(snapshot.get("urgency", OdiseaOSTheme.URGENCY_QUIET))
	var base := String(snapshot.get("default_urgency", ""))
	if base.empty():
		_urgency = OdiseaOSTheme.normalize_urgency(requested)
	else:
		_urgency = OdiseaOSTheme.resolve_urgency(base, requested, _urgency)
	_apply_urgency()

# El unico cambio de color de la urgencia seria el del pulso, y es de alpha (modulate),
# no de tinte: el color de identidad del punto y del widget no se toca.
func _apply_urgency() -> void:
	var token := urgency_token()
	if _urgency_badge != null:
		_urgency_badge.visible = bool(token.get("badge", false))
		_urgency_badge.text = tr("!")
	if float(token.get("pulse_hz", 0.0)) > 0.0:
		set_process(true)
	else:
		_urgency_clock = 0.0
		if _status_dot != null:
			_status_dot.modulate.a = 1.0
		set_process(false)

func _process(delta: float) -> void:
	if float(urgency_token().get("pulse_hz", 0.0)) <= 0.0:
		set_process(false)
		return
	_urgency_clock += delta
	if _status_dot != null:
		_status_dot.modulate.a = urgency_pulse_alpha(_urgency_clock)

# Conectar un boton del widget una sola vez. El host recicla widgets: sin el guard, el
# mismo boton termina con la senal conectada N veces.
func _bind_button(button: Button, method: String) -> void:
	if button != null and not button.is_connected("pressed", self, method):
		button.connect("pressed", self, method)

# Despacha una operacion sobre la pantalla que este widget muestra. HudWidgetAction
# decide si va al control remoto o a SuitOS; el widget no tiene que saberlo.
func _perform(op: String, args: Dictionary = {}) -> void:
	HudWidgetAction.perform(self, _screen_id, op, args)

# Color de fuente solo si cambia: cada override redibuja el Label, y con la fuente con
# outline del tema el motor (3.6 stock) re-empaca en el atlas los glyphs sin contorno en
# cada dibujo. Viene de FlashlightWidget, donde se midio.
func _set_font_color(label: Label, color: Color) -> void:
	if label == null:
		return
	if label.get_color("font_color") != color:
		label.add_color_override("font_color", color)
