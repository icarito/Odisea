extends Control

# Detecta toques directos sobre botones y dispara su señal "pressed".
#
# Con emulate_mouse_from_touch activo (default del proyecto) los botones
# nativos ya reciben los toques como clicks, así que este handler es un
# refuerzo. Para NO robarle eventos de mouse a los botones, el Control vive
# con mouse_filter = IGNORE y escuchamos en _input() en vez de _gui_input(),
# filtrando exclusivamente eventos de toque de pantalla.

# Lista de botones a verificar para toques
var buttons = []

func _input(event):
	if event is InputEventScreenTouch and event.pressed:
		var pos = event.position
		for button in buttons:
			if is_instance_valid(button) and not button.disabled and button.get_global_rect().has_point(pos):
				button.emit_signal("pressed")
				get_tree().set_input_as_handled()
				break
	# Ignorar InputEventScreenDrag y eventos de mouse: los maneja el botón nativo.
