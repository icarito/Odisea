extends Control

onready var UIManager = get_node_or_null("/root/UIManager")

export var joystick_scene: PackedScene = preload("res://scenes/ui/Joystick.tscn")
export var button_texture: Texture = preload("res://assets/ui/touch_button_flat_normal.png")
export var global_ui_scale: float = 1.0

var reference_width = 1920.0
var reference_height = 1080.0

func _ready():
	# Ocultar en plataformas no táctiles
	if not OS.has_touchscreen_ui_hint():
		hide()
		return
	
	# Cargar la configuración de controles
	var layout_data = load_layout_data()
	if layout_data:
		create_controls_from_layout(layout_data)

func load_layout_data():
	var file = File.new()
	# TODO: Permitir al usuario seleccionar su propio layout
	var layout_path = "res://assets/touch_layouts/default.json"
	if not file.file_exists(layout_path):
		print("Default touch layout not found at: ", layout_path)
		return null
	
	file.open(layout_path, File.READ)
	var content = file.get_as_text()
	file.close()
	
	var json_result = JSON.parse(content)
	if json_result.error != OK:
		print("Error parsing touch layout JSON: ", json_result.error_string)
		return null
	
	return json_result.result

func parse_color(hex_color_string: String) -> Color:
	if hex_color_string.begins_with("#"):
		return Color(hex_color_string)
	return Color.white

func create_controls_from_layout(layout_data: Dictionary):
	if not layout_data.has("items"):
		print("Layout data has no 'items' array.")
		return

	var items = layout_data.items
	reference_width = float(layout_data.get("width", 1920.0))
	reference_height = float(layout_data.get("height", 1080.0))

	var left_container = $LeftControls
	var right_container = $RightControls

	for item in items:
		var control_node = null
		var properties = {}
		if item.has("properties"):
			var parsed_props = JSON.parse(item.properties)
			if parsed_props.error == OK:
				properties = parsed_props.result

		match item.itemType:
			"JOYSTICK":
				control_node = joystick_scene.instance()
				control_node.name = item.itemIdentifier
				if UIManager:
					UIManager.register_joystick(control_node)
				if properties.has("handleColor"):
					var handle = control_node.get_node_or_null("Background/Handle")
					if handle:
						handle.self_modulate = parse_color(properties.handleColor)
				if properties.has("backgroundColor"):
					var base = control_node.get_node_or_null("Background")
					if base:
						base.self_modulate = parse_color(properties.backgroundColor)
			"BUTTON":
				var container = Node2D.new()
				container.name = item.itemIdentifier
				var button = TouchScreenButton.new()
				button.name = "Button"
				button.normal = button_texture
				button.pressed = button_texture
				if properties.has("buttonColor"):
					button.modulate = parse_color(properties.buttonColor)
				if properties.has("text"):
					var action_name = "vtc_" + properties.text.to_lower()
					button.action = action_name
				container.add_child(button)
				control_node = container
			_:
				continue

		if control_node:
			# Usar anchors relativos y MarginContainer
			var relative_x = float(item.offsetX) / reference_width
			var relative_y = float(item.offsetY) / reference_height
			
			var container = MarginContainer.new()
			container.name = item.itemIdentifier + "_container"
			container.mouse_filter = Control.MOUSE_FILTER_PASS
			container.anchor_left = relative_x
			container.anchor_top = relative_y
			container.anchor_right = relative_x
			container.anchor_bottom = relative_y
			
			if relative_x < 0.5:
				left_container.add_child(container)
			else:
				right_container.add_child(container)
			
			container.add_child(control_node)
			
			# Escalado
			var item_scale = float(item.get("scale", 1.0)) * global_ui_scale
			if "rect_scale" in control_node:
				control_node.rect_scale = Vector2(item_scale, item_scale)
			elif "scale" in control_node:
				control_node.scale = Vector2(item_scale, item_scale)
			
			if "rotation" in control_node and item.has("rotation"):
				control_node.rotation = float(item.rotation)
			
			# Centrar el control en su ancla
			yield(get_tree(), "idle_frame")
			if "rect_pivot_offset" in control_node:
				control_node.rect_pivot_offset = control_node.rect_size / 2.0
		else:
			print("Failed to create control for item: ", item)

func _on_button_pressed(button_name: String):
	print("Button pressed: ", button_name)
	# Aquí puedes usar Input.parse_input_event para simular una acción del InputMap
	# Ejemplo: var event = InputEventAction.new(); event.action = "ui_accept"; event.pressed = true; Input.parse_input_event(event)
