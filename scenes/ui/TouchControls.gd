extends CanvasLayer

# --- Preloaded Resources ---
const JoystickScene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const CirclePainter = preload("res://scripts/ui/CirclePainter.gd")

# --- OnReady References ---
onready var left_panel = $LeftPanel
onready var right_panel = $RightPanel

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
	var scale_factor = 1.0
	var screen_aspect = screen_size.x / screen_size.y
	var ref_aspect = ref_size.x / ref_size.y

	if screen_aspect > ref_aspect:
		scale_factor = screen_size.y / ref_size.y
	else:
		scale_factor = screen_size.x / ref_size.x

	var scaled_canvas_size = ref_size * scale_factor
	var offset = Vector2((screen_size.x - scaled_canvas_size.x) / 2.0, screen_size.y - scaled_canvas_size.y)

	# --- 2. Create and Position UI Elements ---
	for element_data in elements:
		print("Procesando elemento:", element_data)
		# Adaptar campos del formato DroidPad
		var id = element_data.get("itemIdentifier", element_data.get("id", ""))
		var type = element_data.get("itemType", element_data.get("type", ""))
		var x = element_data.get("offsetX", element_data.get("x", 0))
		var y = element_data.get("offsetY", element_data.get("y", 0))
		var scale = float(element_data.get("scale", 1.0))
		var w = element_data.get("w", 100) * scale
		var h = element_data.get("h", 100) * scale
		if element_data.has("w") and element_data.has("h"):
			w = float(element_data["w"]) * scale
			h = float(element_data["h"]) * scale
		elif element_data.has("width") and element_data.has("height"):
			w = float(element_data["width"]) * scale
			h = float(element_data["height"]) * scale
		else:
			# Si no hay w/h, usar valores por defecto según tipo
			if type == "JOYSTICK":
				w = 180 * scale
				h = w
			elif type == "BUTTON":
				w = 120 * scale
				h = w
			else:
				w = 100 * scale
				h = 100 * scale

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

		print("Creando control:", type, "id:", id, "x:", x, "y:", y, "w:", w, "h:", h, "props:", props)
		var control_node = _create_element({"type": type, "id": id, "label": props.get("text", id), "min": props.get("min", 0), "max": props.get("max", 100), "value": props.get("value", 0)})
		if not is_instance_valid(control_node):
			print("No se pudo instanciar control para", id)
			continue

		var parent_panel = right_panel if x > ref_size.x / 2 else left_panel
		parent_panel.add_child(control_node)

		control_node.rect_position = Vector2(x, y)
		control_node.rect_size = Vector2(w, h)

		_apply_style(control_node, {"style": props, "type": type})
		_apply_properties(control_node, {"properties": props, "type": type})
		print("Control añadido:", control_node.name, "en panel:", parent_panel.name)

# Creates a control node based on the element data from the JSON.
func _create_element(data: Dictionary) -> Control:
	var type = data.get("type", "")
	var id = data.get("id", "")

	var control_node = null
	match type:
		"JOYSTICK":
			control_node = JoystickScene.instance()
			control_node.name = id

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

	if style.has("stickColor") and node is Joystick:
		 var handle = node.get_node_or_null("Background/Handle")
		 if handle:
			 handle.modulate = Color(style["stickColor"])

# Applies functional properties from the JSON to a control node.
func _apply_properties(node: Control, data: Dictionary):
	var props = data.get("properties", {})
	if props.empty():
		return

	if node is Joystick:
		if props.has("deadzone"):
			node.set_dead_zone_size(props["deadzone"])

func _on_button_pressed(action: String):
	Input.action_press(action)

func _on_button_released(action: String):
	Input.action_release(action)

# Utilidad para parsear color RGBA uint (ej: 0xFFFFFFFF)
func parse_color(raw_color):
	# Espera un entero tipo 0xRRGGBBAA
	if typeof(raw_color) == TYPE_INT:
		var r = float((raw_color >> 24) & 0xFF) / 255.0
		var g = float((raw_color >> 16) & 0xFF) / 255.0
		var b = float((raw_color >> 8) & 0xFF) / 255.0
		var a = float(raw_color & 0xFF) / 255.0
		return Color(r, g, b, a)
	else:
		print("parse_color: valor no soportado:", raw_color)
		return Color(1,1,1,1)
