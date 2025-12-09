extends CanvasLayer

const DEBUG_PREFIX = "[TouchControls]"

# -- NODES --
onready var right_container = $RightControls
onready var left_container = $LeftControls
onready var UIManager = get_node_or_null("/root/UIManager")

# -- CONFIGURATION --
export(String, FILE, "*.tscn") var joystick_scene_path = "res://addons/virtual_joystick/Joystick/Joystick.tscn"
export(String, FILE, "*.json") var layout_path = "res://assets/touch_layouts/elias.json"
export var global_ui_scale_factor: float = 1.0

var button_texture = preload("res://addons/virtual_joystick/Joystick/joystick_circle.png")

# Layout constants
const DIAMOND_RADIUS = 90.0
const DIAMOND_PADDING = Vector2(180, 180)
const BUTTON_SHAPE_RADIUS = 72.0

# -- STATE --
var reference_width = 1920.0
var reference_height = 1080.0
var action_buttons = {} # { identifier: { node, offset, panel } }
var joystick_node = null
var joystick_offset = null

#
# --------------------LIFECYCLE METHODS--------------------
#
func _ready():
	print(DEBUG_PREFIX, " _ready() called. Initializing touch controls.")
	var layout_data = load_layout_data()
	if layout_data:
		print(DEBUG_PREFIX, "Layout data loaded. Creating controls...")
		create_controls_from_layout(layout_data)
		
		# Connect to viewport size changes to keep the layout updated
		get_viewport().connect("size_changed", self, "update_layout")
		# Set the initial layout
		update_layout()
	else:
		printerr(DEBUG_PREFIX, "Failed to load layout data. No controls will be created.")

#
# --------------------LAYOUT AND POSITIONING--------------------
#
func update_layout():
	# Posiciona controles según offsetX/offsetY del JSON, relativo al tamaño del panel correspondiente
	var screen_size = get_viewport().size
	# Ajustar paneles laterales a un tamaño fijo
	if left_container and left_container is Control:
		left_container.anchor_left = 0.0
		left_container.anchor_top = 1.0
		left_container.anchor_right = 0.0
		left_container.anchor_bottom = 1.0
		left_container.margin_left = 20
		left_container.margin_top = -260
		left_container.margin_right = 180
		left_container.margin_bottom = -20
	if right_container and right_container is Control:
		right_container.anchor_left = 1.0
		right_container.anchor_top = 1.0
		right_container.anchor_right = 1.0
		right_container.anchor_bottom = 1.0
		right_container.margin_left = -180
		right_container.margin_top = -260
		right_container.margin_right = -20
		right_container.margin_bottom = -20

	var dynamic_scale = get_dynamic_scale()

	# Posicionar joystick si existe
	if joystick_node and joystick_offset and left_container:
		var panel_size = left_container.rect_size
		var rel_x = joystick_offset.x / reference_width
		var rel_y = joystick_offset.y / reference_height
		var pos = Vector2(rel_x * panel_size.x, rel_y * panel_size.y)
		if joystick_node is Control:
			joystick_node.rect_position = pos
			joystick_node.rect_scale = Vector2(1, 1) * dynamic_scale
		else:
			joystick_node.position = pos
			joystick_node.scale = Vector2(1, 1) * dynamic_scale
		print(DEBUG_PREFIX, "Joystick pos in LeftControls: ", pos)

	# Posicionar botones
	for id in action_buttons.keys():
		var btn_info = action_buttons[id]
		var node = btn_info.node
		var offset = btn_info.offset
		var panel_name = btn_info.panel
		var panel = left_container if panel_name == "left" else right_container
		var panel_size = panel.rect_size
		var rel_x = offset.x / reference_width
		var rel_y = offset.y / reference_height
		# Si está en right panel, rel_x debe ser relativo a la mitad derecha
		if panel_name == "right":
			rel_x = (offset.x - reference_width * 0.5) / (reference_width * 0.5)
		var pos = Vector2(rel_x * panel_size.x, rel_y * panel_size.y)
		
		var base_scale = btn_info.get("base_scale", 1.0)

		if node is Control:
			node.rect_position = pos
			node.rect_scale = Vector2(base_scale, base_scale) * dynamic_scale
		else:
			node.position = pos
			node.scale = Vector2(base_scale, base_scale) * dynamic_scale
		print(DEBUG_PREFIX, "Button ", id, " pos in ", panel_name, ": ", pos)

func get_dynamic_scale() -> float:
	var screen_size = get_viewport().size
	var screen_aspect = screen_size.x / screen_size.y
	var ref_aspect = reference_width / reference_height
	
	var scale_factor = 1.0
	if screen_aspect > ref_aspect:
		scale_factor = screen_size.y / reference_height
	else:
		scale_factor = screen_size.x / reference_width
	
	return min(scale_factor, 1.5) * global_ui_scale_factor

#
# --------------------CONTROL CREATION--------------------
#

func create_controls_from_layout(layout_data: Dictionary):
	if not layout_data.has("controlPadItems"):
		printerr(DEBUG_PREFIX, "Layout data is invalid: missing 'controlPadItems' array.")
		return

	if layout_data.has("controlPad"):
		var control_pad_info = layout_data.controlPad
		reference_width = float(control_pad_info.get("width", 1920.0))
		reference_height = float(control_pad_info.get("height", 1080.0))

	var items = layout_data.controlPadItems
	var joystick_created = false
	for item in items:
		var control_node = null
		var properties = {}
		if item.has("properties"):
			var parsed_props = JSON.parse(item.properties)
			if parsed_props.error == OK:
				properties = parsed_props.result

		if item.itemType == "JOYSTICK" and not joystick_created:
			var joystick_scene = load(joystick_scene_path)
			if not joystick_scene:
				printerr(DEBUG_PREFIX, "Failed to load joystick scene: ", joystick_scene_path)
				continue
			control_node = joystick_scene.instance()
			joystick_node = control_node
			joystick_offset = Vector2(float(item.offsetX), float(item.offsetY))
			var rel_x = float(item.offsetX) / reference_width
			var panel =  left_container if rel_x < 0.5 else right_container
			panel.add_child(control_node)
			joystick_created = true
			if UIManager:
				UIManager.register_joystick(control_node)
			print(DEBUG_PREFIX, "Joystick added to ", "LeftControls" if rel_x < 0.5 else "RightControls", " at offset ", joystick_offset)
		elif item.itemType == "BUTTON":
			var button = TouchScreenButton.new()
			button.name = item.itemIdentifier
			var action_name = "vtc_" + properties.text.to_lower()
			button.action = action_name
			button.normal = button_texture
			# --- Set Button Shape ---
			var circle_shape = CircleShape2D.new()
			circle_shape.radius = BUTTON_SHAPE_RADIUS
			button.shape = circle_shape
			# --- Set Button Color from JSON or fallback ---
			var color = null
			if item.has("color"):
				color = get_color_from_json_value(item.color)
			else:
				match item.itemIdentifier:
					"BTN_A", "BTN_B":
						color = Color(0.2, 0.2, 1.0)
					"BTN_X", "BTN_Y":
						color = Color(1.0, 1.0, 0.2)
			if color == null:
				color = Color(1,1,1,0.7)
			button.modulate = color
			# --- Set Button Size and Background ---
			var scale := 1.0
			if item.has("scale"):
				scale = float(item.scale)
			# button.scale is now set dynamically in update_layout()
			button.modulate.a = 0.7
			var rel_x = float(item.offsetX) / reference_width
			var rel_y = float(item.offsetY) / reference_height
			var panel = left_container if rel_x < 0.5 else right_container
			panel.add_child(button)
			action_buttons[item.itemIdentifier] = {
				"node": button,
				"offset": Vector2(float(item.offsetX), float(item.offsetY)),
				"panel": "left" if rel_x < 0.5 else "right",
				"base_scale": scale
			}
			print(DEBUG_PREFIX, "Button ", item.itemIdentifier, " added to ", "LeftControls" if rel_x < 0.5 else "RightControls", " at offset (", item.offsetX, ", ", item.offsetY, ")")

#
# --------------------DATA LOADING AND PARSING--------------------
#
func load_layout_data():
	var file = File.new()
	if not file.file_exists(layout_path):
		printerr(DEBUG_PREFIX, "Layout file not found at path: ", layout_path)
		return null
	
	file.open(layout_path, File.READ)
	var content = file.get_as_text()
	file.close()
	
	var json_result = JSON.parse(content)
	if json_result.error != OK:
		printerr(DEBUG_PREFIX, "Error parsing JSON: ", json_result.error_string)
		return null
	
	return json_result.result

# Note: The original parse_color function is no longer needed as we set colors manually.
# The unhandled_input function can be kept for debugging if desired.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventAction and event.action.begins_with("vtc_"):
		print(DEBUG_PREFIX, "[INPUT] Virtual Action '", event.action, "' Pressed: ", event.is_pressed())

func get_color_from_json_value(json_value: float) -> Color:
	# Convertimos el float/int gigante a string hexadecimal
	# En Godot 3.x '%x' maneja ints de 64 bits
	var hex_str = "%x" % int(json_value)
	
	# Tomamos los primeros 8 caracteres (AARRGGBB)
	# A veces el string puede ser más corto si el alpha es 0, así que rellenamos
	while hex_str.length() < 16:
		hex_str = "0" + hex_str
		
	var argb = hex_str.substr(0, 8)
	return Color(argb) # Godot entiende strings Hex ARGB
