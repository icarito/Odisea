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
			# El toque viene en coordenadas del viewport, pero el boton puede estar bajo
			# un padre escalado (UIScaleCompensator ajusta la UI cuando baja la escala de
			# render), y get_global_rect() ignora esa escala. Llevamos el punto al espacio
			# local del boton, que es correcto con o sin escalado.
			if is_instance_valid(button) and not button.disabled and _touches_button(button, pos):
				button.emit_signal("pressed")
				get_tree().set_input_as_handled()
				break
	# Ignorar InputEventScreenDrag y eventos de mouse: los maneja el botón nativo.

func _touches_button(button: Control, viewport_pos: Vector2) -> bool:
	var local: Vector2 = button.get_global_transform_with_canvas().affine_inverse().xform(viewport_pos)
	return Rect2(Vector2.ZERO, button.rect_size).has_point(local)
