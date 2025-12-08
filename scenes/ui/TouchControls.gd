extends CanvasLayer

export var debug_mode = false

const joystick_scene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")

export(String, MULTILINE) var json_data = """
{
	"controlPadItems": [
		{"itemIdentifier":"joystick", "itemType":"JOYSTICK", "position":{"x":0.15, "y":0.5}, "scale": 1.2, "properties":"{\\"backgroundColor\\":\\"#FFFFF36B\\",\\"handleColor\\":\\"#FFFF0000\\"}"},
		{"itemIdentifier":"BTN_A", "itemType":"BUTTON", "position":{"x":0.85, "y":0.25}, "scale": 1.6, "properties":"{\\"text\\":\\"A\\",\\"buttonColor\\":\\"#FF00A000\\"}"},
		{"itemIdentifier":"BTN_B", "itemType":"BUTTON", "position":{"x":0.8, "y":0.75}, "scale": 1.5, "properties":"{\\"text\\":\\"B\\",\\"buttonColor\\":\\"#FF2040FF\\"}"},
		{"itemIdentifier":"BTN_Y", "itemType":"BUTTON", "position":{"x":0.65, "y":0.65}, "scale": 1.3, "properties":"{\\"text\\":\\"Y\\"}"},
		{"itemIdentifier":"BTN_X", "itemType":"BUTTON", "position":{"x":0.7, "y":0.15}, "scale": 1.3, "properties":"{\\"text\\":\\"X\\"}"}
	]
}
"""

func _ready():
	# Ocultar en plataformas que no son táctiles
	if not OS.has_touchscreen_ui_hint():
		hide()
		return

	if debug_mode:
		var stylebox = StyleBoxFlat.new()
		stylebox.set("bg_color", Color(1, 0, 0, 0.1))
		stylebox.set_border_width_all(2)
		stylebox.set("border_color", Color.red)
		$LeftControls.add_stylebox_override("panel", stylebox)
		$RightControls.add_stylebox_override("panel", stylebox)

	var data = JSON.parse(json_data).result
	if data == null:
		push_error("Failed to parse JSON data for TouchControls.")
		return
		
	var items = data.controlPadItems
	for item in items:
		_create_control_item(item)
		
func _create_control_item(item_data: Dictionary):
	var control_node = null
	var properties = {}
	if item_data.has("properties"):
		var parsed_props = JSON.parse(item_data.properties)
		if parsed_props.error == OK:
			properties = parsed_props.result

	match item_data.itemType:
		"JOYSTICK":
			control_node = joystick_scene.instance()
			if UIManager:
				UIManager.register_joystick(control_node)
			if properties.has("handleColor"):
				var handle = control_node.get_node_or_null("Background/Handle")
				if handle: handle.self_modulate = Color(properties.handleColor)
			if properties.has("backgroundColor"):
				var base = control_node.get_node_or_null("Background")
				if base: base.self_modulate = Color(properties.backgroundColor)
		"BUTTON":
			var button = Button.new()
			if properties.has("buttonColor"):
				button.self_modulate = Color(properties.buttonColor)
			button.text = properties.get("text", item_data.itemIdentifier)
			control_node = button
		_:
			push_warning("Unsupported itemType: " + item_data.itemType)
			return

	control_node.name = item_data.itemIdentifier
	
	# Usar un MarginContainer para posicionar y escalar fácilmente
	var container = MarginContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_PASS # Permite que los eventos de mouse pasen a través
	container.anchor_left = item_data.position.x
	container.anchor_top = item_data.position.y
	container.anchor_right = item_data.position.x
	container.anchor_bottom = item_data.position.y
	
	# Determinar si el control va a la izquierda o a la derecha
	if item_data.position.x < 0.5:
		$LeftControls.add_child(container)
	else:
		$RightControls.add_child(container)
		
	container.add_child(control_node)
	
	# Centrar el control en su ancla
	control_node.rect_pivot_offset = control_node.rect_size / 2.0
	
	# Aplicar escala
	var scale_factor = float(item_data.get("scale", 1.0))
	control_node.rect_scale = Vector2.ONE * scale_factor
