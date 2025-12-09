extends CanvasLayer

# --- Preloaded Resources ---
const JoystickScene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const CirclePainter = preload("res://scripts/ui/CirclePainter.gd")

# --- OnReady References ---
onready var left_panel = $HBoxContainer/LeftPanel
onready var right_panel = $HBoxContainer/RightPanel
onready var left_controls = $HBoxContainer/LeftPanel/Controls
onready var right_controls = $HBoxContainer/RightPanel/Controls

# --- Lifecycle ---
func _ready():
	# Wait a frame to ensure the viewport size is accurate.
	yield(get_tree(), "idle_frame")
	print("Building touch controls from JSON layout...")
	_build_controls_from_json()

# --- Private Methods ---

# Main function to parse JSON and build the UI.
func _build_controls_from_json():
	var file = File.new()
	if file.open("res://droidpad_layout.json", File.READ) != OK:
		push_error("Failed to load DroidPad layout file.")
		return

	var json_data = file.get_as_text()
	file.close()

	var parse_result = JSON.parse(json_data)
	if parse_result.error != OK:
		push_error("DroidPad JSON Error: %s" % parse_result.error_string)
		return

	var data = parse_result.result
	print("DroidPad layout loaded successfully.")

	# Adaptación para formato compacto
	var elements = []
	if typeof(data) == TYPE_ARRAY:
		elements = data
	elif data.has("controlPadItems"):
		elements = data["controlPadItems"]
	elif data.has("elements"):
		elements = data["elements"]
	else:
		# Si el JSON es un solo objeto de control
		elements = [data]

	# Determinar tamaño de referencia (canvas)
	var ref_size = Vector2(1280, 720) # Default
	if data.has("controlPad"):
		var pad = data["controlPad"]
		ref_size = Vector2(pad.get("width", 1280), pad.get("height", 720))


	# --- 1. Calculate Responsive Layout ---
	var screen_size = get_viewport().size
	if data.has("controlPad"):
		var pad = data["controlPad"]
		ref_size = Vector2(pad.get("width", 1280), pad.get("height", 720))

	# Panel sizes (aprox. mitad de pantalla)
	var panel_width = screen_size.x / 2.0
	var panel_height = screen_size.y

	# --- 2. Create and Position UI Elements ---
	for element_data in elements:
		print("Procesando elemento:", element_data)
		# Adaptar campos del formato DroidPad
		var id = element_data.get("itemIdentifier", element_data.get("id", ""))
		var type = element_data.get("itemType", element_data.get("type", ""))
		var x = element_data.get("offsetX", element_data.get("x", 0))
		var y = element_data.get("offsetY", element_data.get("y", 0))
		# Ignorar 'scale' del control, solo usar layout base
		var w = 100  # default
		if element_data.has("w"):
			w = float(element_data["w"])
		elif element_data.has("width"):
			w = float(element_data["width"])
		elif type == "JOYSTICK":
			w = 180
		elif type == "BUTTON":
			w = 120

		var h = 100  # default
		if element_data.has("h"):
			h = float(element_data["h"])
		elif element_data.has("height"):
			h = float(element_data["height"])
		elif type == "JOYSTICK":
			h = 180
		elif type == "BUTTON":
			h = 120

		# Determinar panel y posiciones relativas
		var is_right = x > ref_size.x / 2.0
		var parent_controls = right_controls if is_right else left_controls
		var panel_ref_width = ref_size.x / 2.0
		var panel_ref_height = ref_size.y

		# Posición relativa al panel
		var rel_x = x - (panel_ref_width if is_right else 0)
		var rel_y = y

		# Scale factor por panel
		var panel_scale_factor = min(panel_width / panel_ref_width, panel_height / panel_ref_height)

		var scaled_pos = Vector2(rel_x, rel_y) * panel_scale_factor
		var scaled_size = Vector2(w, h) * panel_scale_factor

		# Deserializar properties si existe
		var props = {}
		if element_data.has("properties"):
			if typeof(element_data["properties"]) == TYPE_DICTIONARY:
				props = element_data["properties"]
			elif typeof(element_data["properties"]) == TYPE_STRING:
				var props_parse = JSON.parse(element_data["properties"])
				if props_parse.error == OK:
					props = props_parse.result
				else:
					print("Error parseando properties de", id, ":", props_parse.error_string)

		print("Creando control:", type, "id:", id, "rel_x:", rel_x, "rel_y:", rel_y, "w:", w, "h:", h, "props:", props)
		var control_node = _create_element({"type": type, "id": id, "label": props.get("text", id), "min": props.get("min", 0), "max": props.get("max", 100), "value": props.get("value", 0)})
		if not is_instance_valid(control_node):
			print("No se pudo instanciar control para", id)
			continue

		parent_controls.add_child(control_node)

		control_node.rect_position = scaled_pos
		control_node.rect_size = scaled_size

		_apply_style(control_node, {"style": props, "type": type})
		_apply_properties(control_node, {"properties": props, "type": type})
		print("Control añadido:", control_node.name, "en panel:", parent_controls.get_parent().name, " pos:", scaled_pos, " size:", scaled_size)

# Creates a control node based on the element data from the JSON.
func _create_element(data: Dictionary) -> Control:
	var type = data.get("type", "")
	var id = data.get("id", "")

	var control_node = null
	match type:
		"JOYSTICK":
			control_node = JoystickScene.instance()
			control_node.name = id
			control_node.use_input_actions = true
			# Conectar señales para logging
			control_node.connect("pressed", self, "_on_joystick_pressed", [id])
			control_node.connect("released", self, "_on_joystick_released", [id])

		"BUTTON":
			control_node = Button.new()
			control_node.name = id
			control_node.text = data.get("label", id)
			var action_name = "vtc_" + id
			control_node.connect("button_down", self, "_on_button_pressed", [action_name])
			control_node.connect("button_up", self, "_on_button_released", [action_name])

		"SLIDER":
			control_node = HSlider.new()
			control_node.name = id
			control_node.min_value = data.get("min", 0)
			control_node.max_value = data.get("max", 100)
			control_node.value = data.get("value", 0)

		"TEXT":
			control_node = Label.new()
			control_node.name = id
			control_node.text = data.get("label", "") + ": " + str(data.get("value", ""))

		"SWITCH":
			control_node = CheckBox.new()
			control_node.name = id
			control_node.text = data.get("label", id)
			control_node.pressed = bool(data.get("value", false))

	return control_node

# Positions and scales a control node based on the calculated layout.
func _apply_layout(node: Control, data: Dictionary, scale: float, offset: Vector2, parent: Control):
	var pos_data = data.get("position", {})
	var pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
	var size = Vector2(pos_data.get("width", 100), pos_data.get("height", 100))

	var global_pos = pos * scale + offset
	var final_size = size * scale
	
	node.rect_position = pos * scale - final_size / 2
	node.rect_size = final_size

# Applies colors and other style properties from the JSON to a control node.
func _apply_style(node: Control, data: Dictionary):
	var style = data.get("style", {})
	if style.empty():
		return

	if style.has("backgroundColor"):
		var raw_color = style["backgroundColor"]
		var color = parse_color(raw_color)
		print("parse_color backgroundColor:", raw_color, "->", color)
		if node is Button:
			var icon = CirclePainter.create_circle_texture(node.rect_size.x / 2, color)
			node.icon = icon
		elif node is Joystick:
			var background = node.get_node_or_null("Background")
			if background:
				background.modulate = color

	if style.has("handleColor") and node is Joystick:
		 var handle = node.get_node_or_null("Background/Handle")
		 if handle:
			 handle.modulate = parse_color(style["handleColor"])

# Applies functional properties from the JSON to a control node.
func _apply_properties(node: Control, data: Dictionary):
	var props = data.get("properties", {})
	if props.empty():
		return

	if node is Joystick:
		if props.has("deadzone"):
			node.set_dead_zone_size(props["deadzone"])

func _input(event):
	if event is InputEventScreenTouch:
		print("Touch event:", "pressed" if event.pressed else "released", " at position:", event.position, " index:", event.index)

func _on_button_pressed(action: String):
	print("Button pressed: ", action)
	Input.action_press(action)

func _on_button_released(action: String):
	print("Button released: ", action)
	Input.action_release(action)

func _on_joystick_pressed(id: String):
	print("Joystick pressed: ", id)

func _on_joystick_released(id: String):
	print("Joystick released: ", id)

# Utilidad para parsear color (Int64, ej: 0xAARRGGBB)
func parse_color(raw_color):
	var color_val = 0
	var type = typeof(raw_color)

	if type == TYPE_INT:
		color_val = raw_color
	elif type == TYPE_REAL:
		color_val = int(raw_color)
	elif type == TYPE_STRING:
		color_val = int(raw_color)
	else:
		print("parse_color: valor no soportado (", type, "):", raw_color)
		return Color(1, 1, 1, 1)

	# Asume formato AARRGGBB de 64-bits
	var a = float((color_val >> 56) & 0xFF) / 255.0
	var r = float((color_val >> 48) & 0xFF) / 255.0
	var g = float((color_val >> 40) & 0xFF) / 255.0
	var b = float((color_val >> 32) & 0xFF) / 255.0
	
	# Fallback a formato de 32-bits si el alfa es 0
	if a == 0:
		a = float((color_val >> 24) & 0xFF) / 255.0
		r = float((color_val >> 16) & 0xFF) / 255.0
		g = float((color_val >> 8) & 0xFF) / 255.0
		b = float(color_val & 0xFF) / 255.0

	return Color(r, g, b, a)
