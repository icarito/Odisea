extends CanvasLayer

# --- Preloaded Resources ---
const JoystickScene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const ButtonTexture = preload("res://addons/virtual_joystick/Joystick/joystick_handle.png")

# --- Lifecycle ---
func _ready():
	# Wait a frame to ensure the viewport size is accurate.
	yield(get_tree(), "idle_frame")
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
	var canvas_data = data.get("canvas", {})
	var elements = data.get("elements", [])

	# --- 1. Calculate Responsive Layout ---
	var screen_size = get_viewport().size
	var ref_size = Vector2(canvas_data.get("width", 1), canvas_data.get("height", 1))

	# Determine the scale factor to fit the reference canvas within the screen
	# while maintaining its aspect ratio.
	var scale_factor = 1.0
	var screen_aspect = screen_size.x / screen_size.y
	var ref_aspect = ref_size.x / ref_size.y

	if screen_aspect > ref_aspect:
		# Screen is wider than reference, so height is the limiting dimension.
		scale_factor = screen_size.y / ref_size.y
	else:
		# Screen is taller or has the same aspect, so width is the limiting dimension.
		scale_factor = screen_size.x / ref_size.x

	var scaled_canvas_size = ref_size * scale_factor

	# Calculate offset to anchor the scaled canvas to the bottom-center of the screen.
	var offset = Vector2()
	offset.x = (screen_size.x - scaled_canvas_size.x) / 2.0
	offset.y = screen_size.y - scaled_canvas_size.y

	# --- 2. Create and Position UI Elements ---
	for element_data in elements:
		var control_node = _create_element(element_data)
		if not is_instance_valid(control_node):
			continue

		add_child(control_node)
		_apply_layout(control_node, element_data, scale_factor, offset)
		_apply_style(control_node, element_data)
		_apply_properties(control_node, element_data)

# Creates a control node based on the element data from the JSON.
func _create_element(data: Dictionary) -> Control:
	var type = data.get("type", "")
	var id = data.get("id", "")

	var control_node = null
	match type:
		"JOYSTICK":
			control_node = JoystickScene.instance()
			control_node.name = id
			if UIManager:
				UIManager.register_joystick(control_node)

		"BUTTON":
			control_node = TouchScreenButton.new()
			control_node.name = id
			control_node.normal = ButtonTexture
			# A different texture could be used for the pressed state.
			control_node.pressed = ButtonTexture
			control_node.action = "vtc_" + id

	return control_node

# Positions and scales a control node based on the calculated layout.
func _apply_layout(node: Control, data: Dictionary, scale: float, offset: Vector2):
	var pos_data = data.get("position", {})
	var pos = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
	var size = Vector2(pos_data.get("width", 100), pos_data.get("height", 100))

	var final_pos = pos * scale + offset
	var final_size = size * scale

	node.position = final_pos

	# Scale the node to match the calculated final size.
	var base_size = Vector2.ONE
	if node is TouchScreenButton:
		base_size = node.normal.get_size()
	elif node is Joystick:
		var background = node.get_node_or_null("Background")
		if background:
			base_size = background.rect_size

	if base_size.x > 0 and base_size.y > 0:
		node.scale = final_size / base_size

# Applies colors and other style properties from the JSON to a control node.
func _apply_style(node: Control, data: Dictionary):
	var style = data.get("style", {})
	if style.empty():
		return

	if style.has("backgroundColor"):
		var color = Color(style["backgroundColor"])
		if node is TouchScreenButton:
			node.modulate = color
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
