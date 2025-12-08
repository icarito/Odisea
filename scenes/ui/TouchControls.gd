extends CanvasLayer

export var debug_mode = false
export (float, 0.1, 5.0) var global_ui_scale : float = 1.5


const joystick_scene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const button_texture = preload("res://addons/virtual_joystick/Joystick/joystick_handle.png")


const json_data = """
{"controlPad":{"name":"Elias","orientation":"LANDSCAPE","width":2166,"height":838},"controlPadItems":[{"itemIdentifier":"joystick","controlPadId":7,"offsetX":199.28172,"offsetY":265.61536,"scale":1.0512099,"itemType":"JOYSTICK","properties":"{\\"backgroundColor\\":18446649515709562880,\\"handleColor\\":18446547261128179712,\\"handleRadiusFactor\\":0.79690313}"},{"itemIdentifier":"BTN_A","controlPadId":7,"offsetX":1809.8287,"offsetY":119.001854,"scale":1.5625504,"rotation":0.5697708,"itemType":"BUTTON","properties":"{\\"text\\":\\"A\\",\\"buttonColor\\":18401625609768796160}"},{"itemIdentifier":"BTN_B","controlPadId":7,"offsetX":1740.8557,"offsetY":515.8242,"scale":1.473202,"rotation":1.232296,"itemType":"BUTTON","properties":"{\\"text\\":\\"B\\",\\"buttonColor\\":18402470034698928128}"},{"itemIdentifier":"BTN_Y","controlPadId":7,"offsetX":1356.959,"offsetY":416.8434,"scale":1.3192085,"rotation":-0.16860488,"itemType":"BUTTON","properties":"{\\"text\\":\\"Y\\"}"},{"itemIdentifier":"BTN_X","controlPadId":7,"offsetX":1451.8599,"offsetY":61.90054,"scale":1.2686917,"rotation":-0.6540756,"itemType":"BUTTON","properties":"{\\"text\\":\\"X\\"}"},{"itemIdentifier":"dpad","controlPadId":7,"offsetX":737.75696,"offsetY":353.01068,"scale":0.92181766,"rotation":0.017370217,"itemType":"DPAD","properties":"{\\"backgroundColor\\":18396924098048425984,\\"buttonColor\\":18446594784941309952,\\"style\\":\\"SPLIT\\"}"},{"itemIdentifier":"label","controlPadId":7,"offsetX":980.03436,"offsetY":0.21624961,"scale":2.8302407,"rotation":-0.16309358,"itemType":"LABEL","properties":"{\\"text\\":\\"ODISEA\\"}"}],"connectionConfig":{"controlPadId":7,"connectionType":"UDP","configJson":"{\\"host\\":\\"192.168.18.6\\",\\"port\\":9999}"}}
"""

func parse_color(color_val):
	if typeof(color_val) != TYPE_INT and typeof(color_val) != TYPE_REAL:
		return Color(1, 1, 1, 1)
	var upper_32 = int(float(color_val) / pow(2, 32))
	var a = (upper_32 >> 24) & 0xFF
	var r = (upper_32 >> 16) & 0xFF
	var g = (upper_32 >> 8) & 0xFF
	var b = upper_32 & 0xFF
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

func _ready():
	var left_container = $LeftControls
	var right_container = $RightControls

	if debug_mode:
		var stylebox = StyleBoxFlat.new()
		stylebox.set("bg_color", Color(1, 0, 0, 0.1))
		stylebox.set_border_width_all(2)
		stylebox.set("border_color", Color.red)
		left_container.add_stylebox_override("panel", stylebox)
		right_container.add_stylebox_override("panel", stylebox)

	var data = JSON.parse(json_data).result
	if data == null:
		push_error("Failed to parse JSON data for TouchControls.")
		return
		
	var control_pad = data.controlPad
	var items = data.controlPadItems

	var reference_width = float(control_pad.width)
	var half_reference_width = reference_width / 2.0
	
	var JOYSTICK_BASE_SIZE = Vector2(160, 240)
	
	# Apply the global scale directly to the containers



	for item in items:
		var control_node
		var properties = null
		if item.has("properties"):
			var parsed_props = JSON.parse(item.properties)
			if parsed_props.error == OK:
				properties = parsed_props.result

		match item.itemType:
			"JOYSTICK":
				control_node = joystick_scene.instance()
				control_node.name = item.itemIdentifier
				if debug_mode:
					control_node.debug_mode = true
				if UIManager:
					UIManager.register_joystick(control_node)
				if properties:
					if properties.has("handleColor"):
						var handle = control_node.get_node_or_null("Background/Handle")
						if handle:
							handle.self_modulate = parse_color(properties.handleColor)
					if properties.has("backgroundColor"):
						var base = control_node.get_node_or_null("Background")
						if base:
							base.self_modulate = parse_color(properties.backgroundColor)
			"BUTTON":
				var button = Button.new()
				button.name = item.itemIdentifier
				button.text = properties.text if (properties and properties.has("text")) else item.itemIdentifier
				button.rect_min_size = Vector2(120, 120)
				button.modulate = Color(1, 0.5, 0.2, 1) # Color visible
				button.connect("pressed", self, "_on_button_pressed", [button.name])
				control_node = button
			"DPAD":
				control_node = Control.new() # Placeholder for DPAD, needs specific implementation
				control_node.name = item.itemIdentifier
				if debug_mode:
					var stylebox = StyleBoxFlat.new()
					stylebox.set("bg_color", Color(0, 0, 1, 0.1))
					stylebox.set_border_width_all(2)
					stylebox.set("border_color", Color.blue)
					control_node.add_stylebox_override("panel", stylebox)
			"LABEL":
				control_node = Label.new()
				control_node.name = item.itemIdentifier
				if properties and properties.has("text"):
					control_node.text = properties.text
				control_node.align = Label.ALIGN_CENTER
				control_node.valign = Label.VALIGN_CENTER
				# Optional: set font size or other label properties here
			_:
				continue

		if control_node:
			if item.itemType == "JOYSTICK":
				left_container.add_child(control_node)
				# Posición y escala usando un factor menor para evitar que sea gigante
				var joystick_scale = global_ui_scale * 0.35
				control_node.rect_position = Vector2(item.offsetX, item.offsetY) * joystick_scale
				control_node.rect_scale = Vector2(joystick_scale, joystick_scale)
				if "rotation" in item:
					control_node.rect_rotation = float(item.rotation)
			elif item.itemType == "BUTTON" or item.itemType == "DPAD" or item.itemType == "LABEL":
				right_container.add_child(control_node)
				# Posicionar y escalar dentro del contenedor derecho
				var local_pos_x = item.offsetX * global_ui_scale
				var local_pos_y = item.offsetY * global_ui_scale
				var item_scale = float(item.get("scale", 1.0)) * global_ui_scale

				control_node.rect_position = Vector2(local_pos_x, local_pos_y)
				control_node.rect_scale = Vector2(item_scale, item_scale)

				if "rotation" in item:
					control_node.rect_rotation = float(item.rotation)
		else:
			print("Failed to create control for item: ", item)

func _on_button_pressed(button_name):
	print("Botón presionado:", button_name)
