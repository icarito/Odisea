extends CanvasLayer

const DEBUG_PREFIX = "[TouchControls]"

onready var UIManager = get_node_or_null("/root/UIManager")

export(String, FILE, "*.tscn") var joystick_scene_path = "res://addons/virtual_joystick/Joystick/Joystick.tscn"
export(String, FILE, "*.json") var layout_path = "res://assets/touch_layouts/elias.json"
export var global_ui_scale_factor: float = 1.0

var reference_width = 1920.0
var reference_height = 1080.0

func get_dynamic_scale() -> float:
	var screen_size = get_viewport().size
	var screen_aspect = screen_size.x / screen_size.y
	var ref_aspect = reference_width / reference_height
	
	var scale_factor = 1.0
	if screen_aspect > ref_aspect: # Pantalla más ancha que la referencia
		scale_factor = screen_size.y / reference_height
	else: # Pantalla más alta/estrecha que la referencia
		scale_factor = screen_size.x / reference_width
	
	return min(scale_factor, 1.5) * global_ui_scale_factor

func _ready():
	print(DEBUG_PREFIX, " _ready() called. Initializing touch controls.")
	# Cargar la configuración de controles
	var layout_data = load_layout_data()
	if layout_data:
		print(DEBUG_PREFIX, "Layout data loaded successfully. Creating controls...")
		create_controls_from_layout(layout_data)
	else:
		printerr(DEBUG_PREFIX, "Failed to load layout data. No controls will be created.")

func load_layout_data():
	var file = File.new()
	# TODO: Permitir al usuario seleccionar su propio layout
	print(DEBUG_PREFIX, "Attempting to load layout from: ", layout_path)
	if not file.file_exists(layout_path):
		printerr(DEBUG_PREFIX, "Layout file not found at path: ", layout_path)
		return null
	
	file.open(layout_path, File.READ)
	var content = file.get_as_text()
	file.close()
	
	var json_result = JSON.parse(content)
	if json_result.error != OK:
		printerr(DEBUG_PREFIX, "Error parsing touch layout JSON: ", json_result.error_string, " at line ", json_result.error_line)
		print(DEBUG_PREFIX, "JSON content was: ", content)
		return null
	
	return json_result.result

func parse_color(color_value) -> Color:
	if typeof(color_value) == TYPE_REAL or typeof(color_value) == TYPE_INT: # JSON can parse numbers as float or int
		# El color es un entero de 64 bits. La información ARGB está en los 32 bits superiores.
		# 1. Desplazar 32 bits a la derecha para obtener el valor de 32 bits que nos interesa.
		var color_int32 = int(color_value) # Cast to int to allow bitwise operations
		color_int32 = color_int32 >> 32
		
		# 2. Extraer cada componente (Alfa, Rojo, Verde, Azul) de 8 bits.
		var a = (color_int32 >> 24) & 0xFF
		var r = (color_int32 >> 16) & 0xFF
		var g = (color_int32 >> 8) & 0xFF
		var b = color_int32 & 0xFF
		
		# 3. Crear el color de Godot normalizando los valores (dividiendo por 255.0).
		return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)
	
	return Color.white # Color por defecto si el formato es inesperado

func create_controls_from_layout(layout_data: Dictionary):
	print(DEBUG_PREFIX, "create_controls_from_layout() called.")
	if not layout_data.has("controlPadItems"):
		printerr(DEBUG_PREFIX, "Layout data is invalid: missing 'controlPadItems' array.")
		return

	var items = layout_data.controlPadItems
	print(DEBUG_PREFIX, "Found ", items.size(), " items in layout.")
	
	if layout_data.has("controlPad"):
		var control_pad_info = layout_data.controlPad
		reference_width = float(control_pad_info.get("width", 1920.0))
		reference_height = float(control_pad_info.get("height", 1080.0))
		print(DEBUG_PREFIX, "Layout reference size set to: ", reference_width, "x", reference_height)


	var left_container = $LeftControls
	var right_container = $RightControls

	# Lista para almacenar los nodos que necesitan centrarse después de ser añadidos
	var nodes_to_center = []

	for item in items:
		print(DEBUG_PREFIX, "--- Processing item: ", item.itemIdentifier, " ---")
		var control_node = null
		var properties = {}
		if item.has("properties"):
			var parsed_props = JSON.parse(item.properties)
			if parsed_props.error == OK:
				properties = parsed_props.result

		match item.itemType:
			"JOYSTICK":
				print(DEBUG_PREFIX, "Item type is JOYSTICK. Attempting to instance scene.")
				var joystick_scene = load(joystick_scene_path)
				if not joystick_scene:
					printerr(DEBUG_PREFIX, "Failed to load joystick scene at path: ", joystick_scene_path)
					continue
				
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
				print(DEBUG_PREFIX, "Item type is BUTTON. Creating new button.")
				var container = Node2D.new()
				container.name = item.itemIdentifier
				var button = TouchScreenButton.new()
				button.name = "Button"
				
				# Crear un ColorRect para que el botón sea visible
				var color_rect = ColorRect.new()
				color_rect.rect_min_size = Vector2(128, 128) # Tamaño base, se ajustará con la escala
				button.add_child(color_rect)
				
				if properties.has("buttonColor"):
					color_rect.color = parse_color(properties.buttonColor)
				if properties.has("text"):
					var action_name = "vtc_" + properties.text.to_lower()
					print(DEBUG_PREFIX, "Assigning action '", action_name, "' to button. Ensure this action exists in the Input Map.")
					button.action = action_name
				container.add_child(button)
				control_node = container
			_:
				print(DEBUG_PREFIX, "Skipping unknown itemType: ", item.itemType)
				continue

		if control_node:
			print(DEBUG_PREFIX, "Control node created successfully: ", control_node.name)
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
			print(DEBUG_PREFIX, "Positioning at (", relative_x, ", ", relative_y, ")")
			
			if relative_x < 0.5:
				print(DEBUG_PREFIX, "Adding to LeftControls.")
				left_container.add_child(container)
			else:
				print(DEBUG_PREFIX, "Adding to RightControls.")
				right_container.add_child(container)
			
			container.add_child(control_node)
			
			# Escalado
			print(DEBUG_PREFIX, "Applying scale...")
			var dynamic_scale = get_dynamic_scale()
			var item_scale = float(item.get("scale", 1.0)) * dynamic_scale
			if "rect_scale" in control_node:
				control_node.rect_scale = Vector2(item_scale, item_scale)
			elif "scale" in control_node:
				control_node.scale = Vector2(item_scale, item_scale)
			
			if "rotation" in control_node and item.has("rotation"):
				control_node.rotation = float(item.rotation)
			
			# Añadir a la lista para centrar más tarde
			nodes_to_center.append(control_node)
		else:
			printerr(DEBUG_PREFIX, "Failed to create control node for item: ", item)

	# Esperar a que todos los nodos se hayan añadido al árbol de escenas
	print(DEBUG_PREFIX, "Waiting for idle frame to center all control pivots.")
	yield(get_tree(), "idle_frame")
	_center_pivots(nodes_to_center)

func _center_pivots(nodes: Array):
	print(DEBUG_PREFIX, "Centering pivots for ", nodes.size(), " controls.")
	for control_node in nodes:
		if "rect_pivot_offset" in control_node and control_node.rect_size != Vector2.ZERO:
			control_node.rect_pivot_offset = control_node.rect_size / 2.0
			print(DEBUG_PREFIX, "Pivot for '", control_node.name, "' centered at: ", control_node.rect_pivot_offset)

func _on_button_pressed(button_name: String):
	# Esta función es un ejemplo, los TouchScreenButton no emiten esta señal.
	# Disparan acciones del InputMap directamente.
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		print(DEBUG_PREFIX, "Screen touch/drag event detected at position: ", event.position)
	elif event is InputEventAction:
		if event.action.begins_with("vtc_"):
			print(DEBUG_PREFIX, "Virtual Action Triggered: '", event.action, "' Pressed: ", event.is_pressed())
