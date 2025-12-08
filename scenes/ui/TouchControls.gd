extends CanvasLayer

export var debug_mode = false
export (float, 0.1, 5.0) var global_ui_scale : float = 1.0

const joystick_scene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const button_texture = preload("res://addons/virtual_joystick/Joystick/joystick_handle.png")

export(String, MULTILINE) var json_data = """
{
	"controlPad":{"name":"Elias","orientation":"LANDSCAPE","width":2166,"height":838},
	"controlPadItems":[
		{"itemIdentifier":"joystick","offsetX":199.28172,"offsetY":265.61536,"scale":0.7,"itemType":"JOYSTICK","properties":"{\"backgroundColor\":18446649515709562880,\"handleColor\":18446547261128179712}"},
		{"itemIdentifier":"BTN_A","offsetX":1809.8287,"offsetY":119.001854,"scale":2.0,"rotation":0.5697708,"itemType":"BUTTON","properties":"{\"text\":\"A\",\"buttonColor\":18401625609768796160}"},
		{"itemIdentifier":"BTN_B","offsetX":1740.8557,"offsetY":515.8242,"scale":2.0,"rotation":1.232296,"itemType":"BUTTON","properties":"{\"text\":\"B\",\"buttonColor\":18402470034698928128}"},
		{"itemIdentifier":"BTN_Y","offsetX":1356.959,"offsetY":416.8434,"scale":2.0,"rotation":-0.16860488,"itemType":"BUTTON","properties":"{\"text\":\"Y\"}"},
		{"itemIdentifier":"BTN_X","offsetX":1451.8599,"offsetY":61.90054,"scale":2.0,"rotation":-0.6540756,"itemType":"BUTTON","properties":"{\"text\":\"X\"}"}
	]
}
"""

func parse_color(color_val):
	if typeof(color_val) != TYPE_INT and typeof(color_val) != TYPE_REAL:
		return Color.white
	var upper_32 = int(float(color_val) / pow(2, 32))
	var a = (upper_32 >> 24) & 0xFF
	var r = (upper_32 >> 16) & 0xFF
	var g = (upper_32 >> 8) & 0xFF
	var b = upper_32 & 0xFF
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

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
		
	var control_pad = data.get("controlPad", {})
	var items = data.controlPadItems
	
	var ref_width = float(control_pad.get("width", 1920))
	var ref_height = float(control_pad.get("height", 1080))
	
	for item in items:
		_create_control_item(item, ref_width, ref_height)
		
func _create_control_item(item_data: Dictionary, ref_width: float, ref_height: float):
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
				var handle = control_node.get_node("Background/Handle")
				if handle: handle.self_modulate = parse_color(properties.handleColor)
			if properties.has("backgroundColor"):
				var base = control_node.get_node("Background")
				if base: base.self_modulate = parse_color(properties.backgroundColor)
		"BUTTON":
			var button = TextureButton.new()
			button.texture_normal = button_texture
			button.expand = true
			button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			if properties.has("buttonColor"):
				button.self_modulate = parse_color(properties.buttonColor)
			
			var label = Label.new()
			label.text = properties.get("text", item_data.itemIdentifier)
			label.align = Label.ALIGN_CENTER
			label.valign = Label.VALIGN_CENTER
			label.anchor_right = 1.0
			label.anchor_bottom = 1.0
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(label)
			
			# Conectar señal para verificar que funciona
			button.connect("pressed", self, "_on_button_pressed", [item_data.itemIdentifier])
			
			control_node = button
		_:
			push_warning("Unsupported itemType: " + item_data.itemType)
			return

	control_node.name = item_data.itemIdentifier
	control_node.mouse_filter = Control.MOUSE_FILTER_STOP # Asegura que el botón capture el clic
	
	# Usar un MarginContainer para posicionar y escalar fácilmente
	var container = MarginContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_PASS # Permite que los eventos de mouse pasen a través
	var relative_x = float(item_data.offsetX) / ref_width
	var relative_y = float(item_data.offsetY) / ref_height
	container.anchor_left = relative_x
	container.anchor_top = relative_y
	container.anchor_right = relative_x
	container.anchor_bottom = relative_y
	
	# Determinar si el control va a la izquierda o a la derecha
	if relative_x < 0.5:
		$LeftControls.add_child(container)
	else:
		$RightControls.add_child(container)
		
	container.add_child(control_node)
	
	# Centrar el control en su ancla
	# Esperar un fotograma para que rect_size se calcule correctamente
	yield(get_tree(), "idle_frame")
	control_node.rect_pivot_offset = control_node.rect_size / 2.0
	
	if item_data.has("rotation"):
		control_node.rect_rotation = rad2deg(float(item_data.rotation))
	
	# Aplicar escala
	var scale_factor = float(item_data.get("scale", 1.0)) * global_ui_scale
	control_node.rect_scale = Vector2.ONE * scale_factor

func _on_button_pressed(button_name: String):
	print("Button pressed: ", button_name)
	# Aquí puedes usar Input.parse_input_event para simular una acción del InputMap
	# Ejemplo: var event = InputEventAction.new(); event.action = "ui_accept"; event.pressed = true; Input.parse_input_event(event)
