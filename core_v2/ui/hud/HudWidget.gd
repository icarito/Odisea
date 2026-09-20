extends PanelContainer
class_name HudWidget

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
#   extends HudWidget
#   class_name MiWidget
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

# Los tres nodos que comparten todos los widgets con escena. get_node_or_null: un widget
# puede no tener cabecera (CryoPodWidget dibuja la suya) y eso no es un error.
onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")

# La identidad de la pantalla que este widget esta mostrando. Sale de la lectura, asi que
# el mismo widget sirve para varias instancias de la misma clase de pantalla.
var _screen_id: String = ""

# Punto de entrada del host. Se mantiene por compatibilidad: el host prueba
# update_snapshot primero y set_snapshot despues.
func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	_screen_id = String(snapshot.get("id", _screen_id))
	if _title_label != null:
		_title_label.text = String(snapshot.get("title", default_title()))
	if is_offline(snapshot):
		_set_dot(OdiseaOSTheme.STATE_OFFLINE)
		_render_offline()
		return
	_render(snapshot)

# --- a implementar por cada widget -----------------------------------------------

# Lo que dice la cabecera cuando la lectura no trae titulo.
func default_title() -> String:
	return tr("Pantalla")

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
