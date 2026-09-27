extends PanelContainer
class_name InteractableSlotWidget

# InteractableSlotWidget.gd - Widget de slot de un interactuable fijado (valvula, boton, etc.).
# O widget contextual del pie (CONTEXT_SLOT / CONTEXT_WIDGET_NAME).
# Soporta degradacion por distancia via signal_strength (0..1) y estado FUERA_DE_RANGO.

const ICON_SIZE := Vector2(34, 34)
const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

var _icon: TextureRect = null
var _title: Label = null
var _status: Label = null
var _description: Label = null
var _action: Label = null

var _signal_strength: float = 1.0
var _is_fuera_de_rango: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_constant_override("separation", 6)
	add_child(row)
	var frame := Panel.new()
	frame.name = "Icon"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.rect_min_size = ICON_SIZE
	row.add_child(frame)
	_icon = TextureRect.new()
	_icon.name = "Texture"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand = true
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	frame.add_child(_icon)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title)
	_status = Label.new()
	_status.name = "Status"
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.visible = false
	box.add_child(_status)
	_description = Label.new()
	_description.name = "Description"
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.visible = false
	box.add_child(_description)
	_action = Label.new()
	_action.name = "Action"
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_action)

func set_snapshot(snapshot: Dictionary) -> void:
	update_snapshot(snapshot)

func update_snapshot(snapshot: Dictionary) -> void:
	if is_instance_valid(_title):
		_title.text = String(snapshot.get("title", ""))
	if is_instance_valid(_description):
		var text := String(snapshot.get("description", ""))
		_description.text = text
		_description.visible = not text.empty()
	if is_instance_valid(_action):
		_action.text = String(snapshot.get("action", ""))
	if is_instance_valid(_icon):
		var texture = snapshot.get("icon", null)
		_icon.texture = texture if texture is Texture else null

	if snapshot.has("signal_strength"):
		_signal_strength = clamp(float(snapshot.get("signal_strength", 1.0)), 0.0, 1.0)
	else:
		_signal_strength = 1.0

	var out_flag: bool = bool(snapshot.get("out_of_range", false))
	var status_str: String = String(snapshot.get("status", ""))
	_is_fuera_de_rango = out_flag or status_str == "FUERA_DE_RANGO" or (_signal_strength <= 0.0 and not is_offline(snapshot))

	_apply_signal_visuals(snapshot)

func is_offline(snapshot: Dictionary) -> bool:
	return String(snapshot.get("source", "online")) == "offline"

func get_signal_strength() -> float:
	return _signal_strength

func is_fuera_de_rango() -> bool:
	return _is_fuera_de_rango

func _apply_signal_visuals(snapshot: Dictionary) -> void:
	if is_offline(snapshot):
		if is_instance_valid(_status):
			_status.text = "[OFFLINE]"
			_status.visible = true
			_status.add_color_override("font_color", OdiseaOSTheme.STATE_OFFLINE)
		modulate.a = 0.5
		return

	if _is_fuera_de_rango:
		if is_instance_valid(_status):
			_status.text = "[FUERA DE RANGO]"
			_status.visible = true
			_status.add_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		modulate.a = 0.25
		return

	if is_instance_valid(_status):
		_status.visible = false

	if _signal_strength >= 0.8:
		modulate.a = 1.0
	elif _signal_strength >= 0.3:
		modulate.a = _signal_strength
	else:
		var flicker: float = 0.75 + 0.25 * sin(_signal_strength * 62.83)
		modulate.a = clamp(_signal_strength * flicker, 0.15, 0.8)
