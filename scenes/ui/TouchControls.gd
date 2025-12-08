extends CanvasLayer

const joystick_scene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const button_texture = preload("res://addons/virtual_joystick/Joystick/joystick_handle.png")

const json_data = """
{"controlPad":{"name":"Elias","orientation":"LANDSCAPE","width":2166,"height":838},"controlPadItems":[{"itemIdentifier":"joystick","controlPadId":7,"offsetX":199.28172,"offsetY":265.61536,"scale":1.0512099,"itemType":"JOYSTICK","properties":"{\\"backgroundColor\\":18446649515709562880,\\"handleColor\\":18446547261128179712,\\"handleRadiusFactor\\":0.79690313}"},{"itemIdentifier":"BTN_A","controlPadId":7,"offsetX":1809.8287,"offsetY":119.001854,"scale":1.5625504,"rotation":0.5697708,"itemType":"BUTTON","properties":"{\\"text\\":\\"A\\",\\"buttonColor\\":18401625609768796160}"},{"itemIdentifier":"BTN_B","controlPadId":7,"offsetX":1740.8557,"offsetY":515.8242,"scale":1.473202,"rotation":1.232296,"itemType":"BUTTON","properties":"{\\"text\\":\\"B\\",\\"buttonColor\\":18402470034698928128}"},{"itemIdentifier":"BTN_Y","controlPadId":7,"offsetX":1356.959,"offsetY":416.8434,"scale":1.3192085,"rotation":-0.16860488,"itemType":"BUTTON","properties":"{\\"text\\":\\"Y\\"}"},{"itemIdentifier":"BTN_X","controlPadId":7,"offsetX":1451.8599,"offsetY":61.90054,"scale":1.2686917,"rotation":-0.6540756,"itemType":"BUTTON","properties":"{\\"text\\":\\"X\\"}"},{"itemIdentifier":"dpad","controlPadId":7,"offsetX":737.75696,"offsetY":353.01068,"scale":0.92181766,"rotation":0.017370217,"itemType":"DPAD","properties":"{\\"backgroundColor\\":18396924098048425984,\\"buttonColor\\":18446594784941309952,\\"style\\":\\"SPLIT\\"}"},{"itemIdentifier":"label","controlPadId":7,"offsetX":980.03436,"offsetY":0.21624961,"scale":2.8302407,"rotation":-0.16309358,"itemType":"LABEL","properties":"{\\"text\\":\\"ODISEA\\"}"}],"connectionConfig":{"controlPadId":7,"connectionType":"UDP","configJson":"{\\"host\\":\\"192.168.18.6\\",\\"port\\":9999}"}}
"""

# The color values are 64-bit integers, but Godot's bitwise operations work on 32 bits.
# We can extract the color by treating the value as a float and dividing to get the upper 32 bits.
func parse_color(color_val):
	if typeof(color_val) != TYPE_INT and typeof(color_val) != TYPE_REAL:
		return Color(1, 1, 1, 1) # Return white for invalid types

	# Use floating point division to get the upper 32 bits of the 64-bit value
	var upper_32 = int(float(color_val) / pow(2, 32))

	# The format seems to be ARGB in the high bits
	var a = (upper_32 >> 24) & 0xFF
	var r = (upper_32 >> 16) & 0xFF
	var g = (upper_32 >> 8) & 0xFF
	var b = upper_32 & 0xFF
	
	return Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)


func _ready():
	var data = JSON.parse(json_data).result
	if data == null:
		push_error("Failed to parse JSON data for TouchControls.")
		return
		
	var control_pad = data.controlPad
	var items = data.controlPadItems

	var reference_width = float(control_pad.width)
	var reference_height = float(control_pad.height)
	var screen_size = get_viewport().get_visible_rect().size

	# 1. Calculate a scale factor to fit reference canvas to screen, preserving aspect ratio.
	var scale_factor = 1.0
	var screen_aspect = screen_size.x / screen_size.y
	var ref_aspect = reference_width / reference_height

	if screen_aspect > ref_aspect:
		# Screen is wider than reference, so height is the limiting dimension.
		scale_factor = screen_size.y / reference_height
	else:
		# Screen is taller or has same aspect, so width is the limiting dimension.
		scale_factor = screen_size.x / reference_width
	
	# Clamp scale factor as requested "not too much"
	scale_factor = min(scale_factor, 1.5)

	# 2. Create containers for left and right controls as requested.
	var left_container = Control.new()
	left_container.name = "LeftControls"
	add_child(left_container)

	var right_container = Control.new()
	right_container.name = "RightControls"
	add_child(right_container)
	
	var half_reference_width = reference_width / 2.0

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
				var container = Node2D.new()
				container.name = item.itemIdentifier
				var button = TouchScreenButton.new()
				button.name = "Button"
				button.normal = button_texture
				button.pressed = button_texture
				if properties:
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
			var parent_container = left_container if item.offsetX < half_reference_width else right_container
			parent_container.add_child(control_node)

			var item_scale = float(item.get("scale", 1.0))
			var final_scale = Vector2(item_scale, item_scale) * scale_factor
			if "rect_scale" in control_node:
				control_node.rect_scale = final_scale
			elif "scale" in control_node:
				control_node.scale = final_scale

			if "rotation" in control_node and item.has("rotation"):
				control_node.rotation = float(item.rotation)

			var center_pos = Vector2()
			var scaled_offsetX = item.offsetX * scale_factor
			var scaled_offsetY = item.offsetY * scale_factor

			if item.offsetX < half_reference_width:
				center_pos.x = scaled_offsetX
			else:
				var scaled_offset_from_right = (reference_width - item.offsetX) * scale_factor
				center_pos.x = screen_size.x - scaled_offset_from_right
			center_pos.y = screen_size.y - scaled_offsetY

			if control_node is Control:
				var control_size = Vector2.ZERO
				var background_node = control_node.get_node_or_null("Background")
				if background_node:
					control_size = background_node.rect_size * control_node.rect_scale
				if control_size == Vector2.ZERO:
					control_node.rect_position = center_pos
				else:
					control_node.rect_position = center_pos - (control_size / 2.0)
			else:
				control_node.position = center_pos
		else:
			print("Failed to create control for item: ", item)
