extends Button
class_name TouchActionButton

export(String) var action_name := ""
# Si es true, el boton arranca "gris" (modulate atenuado) y solo se enciende
# mientras el jugador tiene un interactuable en rango (PlayerControllerV2
# interactable_in_range/out_of_range). Reemplaza al shader de highlight/
# proximity que antes duplicaba meshes por cada prop en rango.
export(bool) var dims_when_unavailable := false

const _DIM_MODULATE := Color(0.5, 0.5, 0.5, 0.6)
const _ACTIVE_MODULATE := Color(1, 1, 1, 1)

var _touch_index := -1
var _player: Node = null

func _ready() -> void:
	add_to_group("touch_control")
	# _process() se auto-habilita porque el script lo define (Godot 3.x), asi que
	# hay que apagarlo explicitamente para los botones que no dimean: si no,
	# igual encuentran al player y se conectan a sus senales de interactuable.
	set_process(dims_when_unavailable)
	if dims_when_unavailable:
		modulate = _DIM_MODULATE
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

func _process(_delta: float) -> void:
	# El player no existe todavia al momento del _ready() de este boton (orden
	# de instanciacion de la escena), asi que reintenta hasta encontrarlo y
	# despues se apaga solo.
	if is_instance_valid(_player):
		set_process(false)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		_player.connect("interactable_in_range", self, "_on_interactable_in_range")
		_player.connect("interactable_out_of_range", self, "_on_interactable_out_of_range")
		set_process(false)

func _on_interactable_in_range(_text: String) -> void:
	modulate = _ACTIVE_MODULATE

func _on_interactable_out_of_range() -> void:
	modulate = _DIM_MODULATE

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
