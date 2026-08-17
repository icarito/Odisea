extends Button
class_name TouchActionButton

export(String) var action_name := ""

var _touch_index := -1

func _ready() -> void:
	add_to_group("touch_control")
	# Sin esto, tocar el boton le da foco de teclado/gamepad y Godot dibuja el
	# StyleBox "focus" del tema por defecto (un rectangulo recto) encima del
	# StyleBox redondeado del boton hasta que otro control se lo saca. Estos
	# botones son solo touch, no navegan por foco.
	focus_mode = Control.FOCUS_NONE
	# El motor emula un mouse a partir del touch (input_devices/pointing/
	# emulate_mouse_from_touch, en true por defecto), y ese mouse emulado nunca
	# "sale" del boton al levantar el dedo -no hay a donde moverlo-, asi que el
	# boton queda trabado en estado hover indefinidamente despues de cada toque.
	# Como ningun boton define su propio StyleBox de hover, cae al del tema por
	# defecto: un rectangulo recto sin el corner_radius de "normal"/"pressed",
	# que es exactamente el "se vuelve cuadrado" reportado. Copiar el estilo de
	# "normal" a "hover" (si no hay uno propio) evita ese fallback en cualquier
	# boton que use este script.
	if not has_stylebox_override("hover") and has_stylebox_override("normal"):
		add_stylebox_override("hover", get_stylebox("normal"))
	if not has_stylebox_override("disabled") and has_stylebox_override("normal"):
		add_stylebox_override("disabled", get_stylebox("normal"))
	# Mismo problema con el color de letra: el tema default usa un tostado de bajo
	# contraste para "normal" y CIAN para "hover" (Theme/retro_scifi.tres), y el hover
	# trabado (ver arriba) deja el ultimo boton tocado con el texto cian pegado. Un
	# blanco fijo en los cuatro estados da contraste parejo contra cualquier color de
	# fondo de boton y elimina el cambio de color al quedar en hover.
	for state in ["font_color", "font_color_hover", "font_color_pressed", "font_color_disabled"]:
		if not has_color_override(state):
			add_color_override(state, Color.white)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		var rect = get_global_rect()
		if event.pressed:
			if rect.has_point(event.position) and _touch_index == -1:
				_touch_index = event.index
				_press()
				get_tree().set_input_as_handled()
		elif event.index == _touch_index:
			_release()
			_touch_index = -1
			get_tree().set_input_as_handled()
	
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			var rect = get_global_rect()
			if not rect.has_point(event.position):
				_release()
				_touch_index = -1

func _press() -> void:
	pressed = true
	if action_name != "":
		Input.action_press(action_name)

func _release() -> void:
	pressed = false
	if action_name != "":
		Input.action_release(action_name)
