extends PanelContainer
class_name InteractableSlotWidget

# InteractableSlotWidget.gd - Widget de slot de un interactuable fijado (valvula, boton, etc.). Misma
# ficha que el prompt del pie: cuadrado de icono, nombre, descripcion y el verbo del estado. Lo
# completa update_snapshot() con el snapshot del InteractableSlotScreen.

const ICON_SIZE := Vector2(34, 34)

var _icon: TextureRect = null
var _title: Label = null
var _description: Label = null
var _action: Label = null

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
	_description = Label.new()
	_description.name = "Description"
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_description.visible = false
	box.add_child(_description)
	_action = Label.new()
	_action.name = "Action"
	_action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_action)

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
