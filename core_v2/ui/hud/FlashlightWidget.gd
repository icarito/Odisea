extends "res://core_v2/ui/hud/HudWidget.gd"
class_name FlashlightWidget

# FlashlightWidget.gd - Widget de slot de la linterna de casco (FD-298).
#
# Migrado a HudWidget: la base se ocupa del titulo, el punto de estado, la rama OFFLINE
# (Manual §7) y el despacho de la accion. Aca queda solo lo propio de la linterna.
#
# Paso "Linterna en ImGui": con el modulo disponible (ClassDB.class_exists("ImGuiCanvas"))
# este widget agrega un FlashlightWidgetImGui.gd (Node2D) que dibuja el MISMO contenido
# desde el mismo _last_snapshot, y esconde los Controls viejos (Margin) para no duplicar.
# Sin el modulo (release pinneado sin imgui, o este mismo widget copiado al control
# remoto si ese dispositivo no lo trae) sigue el camino de Controls de siempre: no cambia
# el contrato con SuitOSWidgetHost/HudWidgetAction (update_snapshot -> _perform).
# load() diferido: precompilar FlashlightWidgetImGui.gd (extends ImGuiCanvas) rompe la
# compilacion del .gd en el binario sin el modulo, igual que CryoPodUI._build_imgui_screen.
const FlashlightWidgetImGuiPath := "res://core_v2/ui/hud/FlashlightWidgetImGui.gd"

onready var _meter_label: Label = get_node_or_null("Margin/VBox/MeterLabel")
onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusRow/StatusLabel")
onready var _toggle_button: Button = get_node_or_null("Margin/VBox/StatusRow/ToggleButton")
onready var _margin: Control = get_node_or_null("Margin")

# Ultima lectura, para que el canvas ImGui (que no es un HudWidget) pueda leerla sin
# reimplementar la rama OFFLINE. La escribe _render()/_render_offline(); no reemplaza a
# set_snapshot()/update_snapshot(), que siguen siendo el contrato con el host.
var _last_snapshot := {}
var _imgui_widget = null

func _ready() -> void:
	_bind_button(_toggle_button, "_on_toggle_pressed")
	if ClassDB.class_exists("ImGuiCanvas"):
		call_deferred("_build_imgui_widget")

func _build_imgui_widget() -> void:
	var canvas_script = load(FlashlightWidgetImGuiPath)
	if canvas_script == null:
		return
	var canvas = canvas_script.new()
	canvas.name = "FlashlightWidgetImGui"
	canvas.widget = self
	add_child(canvas)
	if _margin != null:
		_margin.visible = false
	# El panel ImGui pinta su propio fondo (SURFACE_PANEL); el "panel" del tema detras
	# duplicaba el borde/relleno.
	add_stylebox_override("panel", StyleBoxEmpty.new())
	# Bajar al tamano de diseno del panel: el size que dejo el primer layout con
	# Controls visibles era mas alto y el host re-ubica el widget en el slot al
	# escuchar resized (con el size viejo el fit del slot encogia el widget de mas).
	rect_size = canvas.panel_size()
	set_meta("hud_slot_centered", true)
	# SuitOSWidgetHost.gd: el arrastre de este widget no puede depender de que le
	# llegue el evento (ImGuiCanvas lo atrapa antes, ver SuitOSWidgetHost._poll_imgui_pointer);
	# esta marca le dice al host que sondee el puntero en vez de esperar gui_input.
	set_meta("hud_uses_imgui_pointer_poll", true)
	_imgui_widget = canvas

# Snapshot leido por FlashlightWidgetImGui en cada imgui_frame.
func snapshot() -> Dictionary:
	return _last_snapshot

# Punto de entrada del canvas ImGui para la misma accion que el boton viejo.
func toggle_action() -> void:
	_perform("toggle")

# Rects (en coordenadas locales de este Control) de los botones que pinta el canvas
# ImGui, si tiene alguno (FlashlightWidgetImGui.gd ya no: T12 le saco el boton
# ENCENDER/APAGAR, el widget de slot quedo de solo lectura). Generico por si algun otro
# widget ImGui de slot agrega uno mas adelante: sin rects, HudWidgetAction.pointer_on_button()
# no ve ningun boton y el tap se atribuye al widget entero (abre su pantalla).
func imgui_button_hit_rects() -> Array:
	if _imgui_widget == null or not is_instance_valid(_imgui_widget):
		return []
	if not _imgui_widget.has_method("button_hit_rects"):
		return []
	var origin: Vector2 = (_imgui_widget as Node2D).position
	var rects: Array = []
	for r in _imgui_widget.button_hit_rects():
		var rect: Rect2 = r
		rects.append(Rect2(origin + rect.position, rect.size))
	return rects

func default_title() -> String:
	return tr("Linterna")

func default_screen_id() -> String:
	return "player:flashlight"

func _render(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	var on: bool = bool(snapshot.get("on", false))
	var low: bool = bool(snapshot.get("low", false))
	var battery: float = float(snapshot.get("battery", 100.0))
	var battery_max: float = float(snapshot.get("battery_max", 100.0))

	if _toggle_button != null:
		_toggle_button.disabled = false
		_toggle_button.text = tr("APAGAR") if on else tr("ENCENDER")

	if on:
		_set_dot(OdiseaOSTheme.STATE_ALARM if low else OdiseaOSTheme.STATE_ACTIVE)
		if _status_label != null:
			_status_label.text = tr("BAT. BAJA") if low else tr("ENCENDIDA")
	else:
		_set_dot(OdiseaOSTheme.STATE_OFFLINE)
		if _status_label != null:
			_status_label.text = tr("APAGADA")

	if _meter_label != null:
		_meter_label.text = _format_battery_bar(battery, battery_max)
		_set_font_color(_meter_label, OdiseaOSTheme.STATE_ALARM if (low and on) else OdiseaOSTheme.INK)

func _render_offline() -> void:
	_last_snapshot = {"source": "offline"}
	if _meter_label != null:
		_meter_label.text = "BAT: [----------]"
	if _status_label != null:
		_status_label.text = tr("OFFLINE")
	if _toggle_button != null:
		_toggle_button.disabled = true
		_toggle_button.text = tr("OFFLINE")

# ASCII: la fuente del tema no trae los bloques (blocks) y la barra salia vacia
# ("BAT: []").
func _format_battery_bar(val: float, max_val: float) -> String:
	if max_val <= 0.0:
		return "BAT: [..........]"
	var ratio := clamp(val / max_val, 0.0, 1.0)
	var total_segments := 10
	var filled_segments := int(round(ratio * total_segments))
	var bar := ""
	for i in range(total_segments):
		if i < filled_segments:
			bar += "|"
		else:
			bar += "."
	return "BAT: [%s]" % bar

func _on_toggle_pressed() -> void:
	_perform("toggle")
