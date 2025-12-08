extends CanvasLayer

const joystick_scene = preload("res://addons/virtual_joystick/Joystick/Joystick.tscn")
const button_texture = preload("res://addons/virtual_joystick/Joystick/joystick_handle.png")

const json_data = """
{"controlPad":{"name":"Elias","orientation":"LANDSCAPE","width":2166,"height":838},"controlPadItems":[{"itemIdentifier":"joystick","controlPadId":7,"offsetX":199.28172,"offsetY":265.61536,"scale":1.0512099,"itemType":"JOYSTICK","properties":"{\\"backgroundColor\\":18446649515709562880,\\"handleColor\\":18446547261128179712,\\"handleRadiusFactor\\":0.79690313}"},{"itemIdentifier":"BTN_A","controlPadId":7,"offsetX":1809.8287,"offsetY":119.001854,"scale":1.5625504,"rotation":0.5697708,"itemType":"BUTTON","properties":"{\\"text\\":\\"A\\",\\"buttonColor\\":18401625609768796160}"},{"itemIdentifier":"BTN_B","controlPadId":7,"offsetX":1740.8557,"offsetY":515.8242,"scale":1.473202,"rotation":1.232296,"itemType":"BUTTON","properties":"{\\"text\\":\\"B\\",\\"buttonColor\\":18402470034698928128}"},{"itemIdentifier":"BTN_Y","controlPadId":7,"offsetX":1356.959,"offsetY":416.8434,"scale":1.3192085,"rotation":-0.16860488,"itemType":"BUTTON","properties":"{\\"text\\":\\"Y\\"}"},{"itemIdentifier":"BTN_X","controlPadId":7,"offsetX":1451.8599,"offsetY":61.90054,"scale":1.2686917,"rotation":-0.6540756,"itemType":"BUTTON","properties":"{\\"text\\":\\"X\\"}"},{"itemIdentifier":"dpad","controlPadId":7,"offsetX":737.75696,"offsetY":353.01068,"scale":0.92181766,"rotation":0.017370217,"itemType":"DPAD","properties":"{\\"backgroundColor\\":18396924098048425984,\\"buttonColor\\":18446594784941309952,\\"style\\":\\"SPLIT\\"}"},{"itemIdentifier":"label","controlPadId":7,"offsetX":980.03436,"offsetY":0.21624961,"scale":2.8302407,"rotation":-0.16309358,"itemType":"LABEL","properties":"{\\"text\\":\\"ODISEA\\"}"}],"connectionConfig":{"controlPadId":7,"connectionType":"UDP","configJson":"{\\"host\\":\\"192.168.18.6\\",\\"port\\":9999}"}}
"""

func _ready():
	var data = JSON.parse(json_data).result
	var control_pad = data.controlPad
	var items = data.controlPadItems

	var reference_width = control_pad.width
	var reference_height = control_pad.height
	var screen_size = get_viewport().size

	for item in items:
		var control_node
		match item.itemType:
			"JOYSTICK":
				control_node = joystick_scene.instance()
				control_node.name = item.itemIdentifier
				UIManager.register_joystick(control_node)
			"BUTTON":
				control_node = TouchScreenButton.new()
				control_node.name = item.itemIdentifier
				control_node.normal = button_texture
				control_node.pressed = button_texture # Placeholder

				if item.has("properties"):
					var properties = JSON.parse(item.properties).result
					if properties.has("text"):
						var action_name = "vtc_" + properties.text.to_lower()
						control_node.action = action_name
			_:
				continue

		add_child(control_node)

		var scale = item.scale
		control_node.scale = Vector2(scale, scale)

		var x_ratio = item.offsetX / reference_width
		var y_ratio = item.offsetY / reference_height

		control_node.position.x = screen_size.x * x_ratio
		control_node.position.y = screen_size.y * y_ratio
		control_node.rotation = item.rotation
