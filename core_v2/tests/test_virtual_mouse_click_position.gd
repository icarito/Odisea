extends GdUnitTestSuite

const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

# El cursor de gamepad mide, dibuja y clampea en coordenadas del VIEWPORT de render.
# SceneTree.input_event() no: pasa por Viewport::_make_input_local(), que aplica
# _get_input_pre_xform() -- escala por size/to_screen_rect.size -- y trata la posicion
# como coordenadas de VENTANA. Con stretch "viewport" (render_resolution * render_scale
# estirado a la pantalla) las dos no coinciden y el click se procesaba lejos del cursor
# dibujado: en el Anbernic, 800x600*escala contra una ventana de 640x480. En escritorio,
# con la ventana del tamaño del viewport, la transformada es identidad y el bug no se ve,
# asi que el test la fuerza.

class PositionSpy:
	extends Node
	var seen := []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			seen.append(event.position)

class ClickSpy:
	extends Node
	var seen := []
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			seen.append(event)

var _restore_stretch := false

func after() -> void:
	if not _restore_stretch:
		return
	_restore_stretch = false
	var settings = get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("apply_render_resolution"):
		settings.apply_render_resolution()

func test_injected_click_keeps_the_cursor_coordinates() -> void:
	var tree := get_tree()
	tree.set_screen_stretch(
		SceneTree.STRETCH_MODE_VIEWPORT,
		SceneTree.STRETCH_ASPECT_EXPAND,
		Vector2(400, 300)
	)
	_restore_stretch = true
	# Precondicion: sin viewport distinto de la ventana el test pasa con el bug puesto.
	assert_vector2(tree.root.size).is_not_equal(OS.window_size)

	var spy := PositionSpy.new()
	add_child(spy)
	var cursor: Control = VirtualMouseScript.attach_to(self)
	cursor._active = true
	cursor._position = Vector2(300, 200)

	var click := InputEventMouseButton.new()
	click.button_index = BUTTON_LEFT
	click.pressed = true
	click.position = cursor._position
	click.global_position = cursor._position
	# Suites previas del mismo proceso (GdUnitSceneRunner, GUI de motion) dejan
	# SceneTree.input_handled en true, y en CI headless no hay eventos de OS que lo
	# reseteen. El root viewport delega en ese flag (handle_input_locally=false en
	# SceneTree) y Viewport.input() corta la entrega: sin resetear, el click inyectado
	# no llega a nadie. Un key event sin foco pasa por el dispatch real, que resetea
	# el flag al inicio y nadie lo consume.
	Input.parse_input_event(InputEventKey.new())
	Input.flush_buffered_events()
	# El flush puede entregar clicks que quedaron encolados por el arranque/UI previa: este test
	# mide SOLO el click inyectado, asi que se descarta lo acumulado hasta aca.
	spy.seen.clear()
	cursor._emit_event(click)

	assert_int(spy.seen.size()).is_equal(1)
	# Por SceneTree.input_event() aca llegaba _position reescalada por viewport/ventana.
	assert_vector2(spy.seen[0]).is_equal(cursor._position)

	cursor.get_parent().queue_free()
	spy.queue_free()

func test_attach_to_reuses_the_existing_cursor() -> void:
	var first: Control = VirtualMouseScript.attach_to(self)
	first.set_process(false)
	first.set_process_input(false)
	first.set_gamepad_cursor_enabled(false)
	first.visible = false
	var second: Control = VirtualMouseScript.attach_to(self)

	assert_object(second).is_same(first)
	assert_int(get_tree().get_nodes_in_group("virtual_mouse").size()).is_equal(1)
	assert_bool(second.is_processing()).is_true()
	assert_bool(second.is_processing_input()).is_true()
	assert_bool(second.gamepad_cursor_enabled).is_true()
	assert_bool(second.visible).is_true()

	first.get_parent().queue_free()

func test_first_gamepad_input_centers_cursor_when_no_mouse_was_used() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	cursor.set_desktop_mouse_mode(true, Vector2.ZERO)

	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_0
	motion.axis_value = 0.5
	cursor._input(motion)

	assert_vector2(cursor._position).is_equal(cursor.get_viewport_rect().size * 0.5)
	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()

# Colgado de la raiz por un menu, el cursor solo vive mientras ese menu esta visible: en juego no
# debe mover la camara con el stick ni convertir A/B en clicks.
func test_cursor_is_inert_while_its_requester_is_hidden() -> void:
	var menu := Control.new()
	add_child(menu)
	menu.hide()
	var cursor: Control = VirtualMouseScript.attach_to(self, menu)
	assert_bool(cursor.is_wanted()).is_false()
	menu.show()
	assert_bool(cursor.is_wanted()).is_true()
	menu.queue_free()
	cursor.get_parent().queue_free()


func test_desktop_mouse_mode_hides_the_system_pointer_and_tracks_its_motion() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	var start := Vector2(140.0, 90.0)
	cursor.set_desktop_mouse_mode(true, start)
	assert_bool(cursor.is_desktop_mouse_mode()).is_true()
	assert_int(cursor._desktop_mouse_restore_mode).is_equal(mouse_mode)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(280.0, 180.0)
	cursor._input(motion)
	assert_vector2(cursor._position).is_equal(motion.position)
	cursor.set_desktop_mouse_mode(false)
	assert_int(Input.get_mouse_mode()).is_equal(mouse_mode)
	cursor.get_parent().queue_free()


# El mouse real siempre toma el control: moverlo cambia el cursor del gamepad por el virtual que
# sigue al puntero, con el del sistema oculto. Antes se soltaba el grab y aparecia el nativo.
func test_real_mouse_motion_switches_the_gamepad_cursor_to_desktop_mode() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	var settable: bool = _mouse_mode_is_settable()
	cursor._active = true
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(210.0, 160.0)
	motion.relative = Vector2(6.0, 0.0)
	cursor._input(motion)
	assert_bool(cursor.is_desktop_mouse_mode()).is_true()
	assert_bool(cursor._active).is_false()
	if settable:
		assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_HIDDEN)
	cursor.set_desktop_mouse_mode(false)
	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()


func test_real_mouse_keeps_cursor_position_when_leaving_gamepad_mode() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var expected := Vector2(123.0, 77.0)
	cursor._active = true
	cursor._position = expected
	var motion := InputEventMouseMotion.new()
	# En modo capturado esta posicion es el centro, no la posicion absoluta del mouse.
	motion.position = cursor.get_viewport_rect().size * 0.5
	motion.relative = Vector2(4.0, 0.0)
	cursor._input(motion)

	assert_bool(cursor.is_desktop_mouse_mode()).is_true()
	assert_vector2(cursor._position).is_equal(expected)
	cursor.get_parent().queue_free()


func _clear_virtual_mice() -> void:
	for node in get_tree().get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(node) and is_instance_valid(node.get_parent()):
			node.get_parent().free()


# El binario headless de CI (Server) ignora set_mouse_mode y deja get_mouse_mode en VISIBLE:
# los asserts del modo nativo solo corren donde el driver lo honra.
func _mouse_mode_is_settable() -> bool:
	var restore: int = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var settable: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(restore)
	return settable


# El juego libera el puntero (ui_cancel / clic derecho) sin ninguna UI: el cursor global se prende
# igual, en modo desktop, y se apaga al recapturar.
func test_released_pointer_shows_the_virtual_cursor_with_no_ui() -> void:
	_clear_virtual_mice()
	var cursor: Control = VirtualMouseScript.ensure_global()
	var mouse_mode: int = Input.get_mouse_mode()
	var settable: bool = _mouse_mode_is_settable()
	VirtualMouseScript.set_pointer_released(true)
	assert_bool(cursor.is_desktop_mouse_mode()).is_true()
	assert_bool(cursor.is_wanted()).is_true()
	assert_bool(cursor.is_processing_input()).is_true()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_true()
	if settable:
		assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_HIDDEN)
	# Si el juego habia recapturado, volver a soltar reafirma HIDDEN: antes el early-return lo
	# dejaba dibujado pero con el puntero grabado (clavado en el centro).
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	VirtualMouseScript.set_pointer_released(true)
	if settable:
		assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_HIDDEN)
	VirtualMouseScript.set_pointer_released(false)
	assert_bool(cursor.is_wanted()).is_false()
	assert_bool(cursor.is_desktop_mouse_mode()).is_false()
	assert_bool(VirtualMouseScript.is_pointer_released()).is_false()
	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().free()


# Estandar de popups: al mostrarse, el popup prende el cursor virtual (modo desktop) sin depender
# de que el juego ya tuviera uno; al ocultarse, lo suelta.
func test_attach_popup_deferred_attaches_on_the_next_idle() -> void:
	# El popup pide el cursor en su _ready, cuando el padre esta armando hijos: el puente diferido
	# lo cuelga recien en el proximo idle, sin "Parent node is busy setting up children".
	_clear_virtual_mice()
	var mouse_mode: int = Input.get_mouse_mode()
	var popup := Control.new()
	add_child(popup)
	popup.visible = true
	VirtualMouseScript.attach_popup_deferred(popup)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var cursors: Array = get_tree().get_nodes_in_group("virtual_mouse")
	assert_int(cursors.size()).is_equal(1)
	assert_bool((cursors[0] as Control).is_wanted()).is_true()
	popup.free()
	_clear_virtual_mice()
	Input.set_mouse_mode(mouse_mode)
	# El modo desktop pudo encolar clicks sinteticos: se drenan aca para no contaminar al test
	# siguiente (que cuenta clicks inyectados).
	Input.flush_buffered_events()


func test_popup_standard_shows_the_virtual_cursor_on_show() -> void:
	_clear_virtual_mice()
	var popup := Control.new()
	add_child(popup)
	popup.visible = false
	var mouse_mode: int = Input.get_mouse_mode()
	var cursor: Control = VirtualMouseScript.attach_popup(popup)
	assert_bool(cursor.is_wanted()).is_false()
	popup.visible = true
	assert_bool(cursor.is_wanted()).is_true()
	assert_bool(cursor.is_desktop_mouse_mode()).is_true()
	popup.visible = false
	cursor._process(0.0)
	assert_bool(cursor.is_wanted()).is_false()
	assert_bool(cursor.is_desktop_mouse_mode()).is_false()
	Input.set_mouse_mode(mouse_mode)
	popup.free()
	cursor.get_parent().free()


# O4: el boton de interactuar (JOY_BUTTON_2 / accion `interact`) clickea izquierdo, sin tocar el
# mapeo directo A/B.
func test_interact_button_emits_a_left_click() -> void:
	var spy := ClickSpy.new()
	add_child(spy)
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	cursor._active = true
	cursor._position = Vector2(210.0, 160.0)
	# Mismo drenado que el test de posicion: input_handled puede venir en true de suites previas.
	Input.parse_input_event(InputEventKey.new())
	Input.flush_buffered_events()
	spy.seen.clear()

	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_2
	press.pressed = true
	cursor._input(press)

	assert_int(spy.seen.size()).is_equal(1)
	assert_int((spy.seen[0] as InputEventMouseButton).button_index).is_equal(BUTTON_LEFT)
	assert_bool((spy.seen[0] as InputEventMouseButton).pressed).is_true()

	# El boton 1 (B) sigue siendo click derecho: no se rompio el mapeo A/B.
	var right := InputEventJoypadButton.new()
	right.button_index = JOY_BUTTON_1
	right.pressed = true
	Input.parse_input_event(InputEventKey.new())
	Input.flush_buffered_events()
	spy.seen.clear()
	cursor._input(right)
	assert_int(spy.seen.size()).is_equal(1)
	assert_int((spy.seen[0] as InputEventMouseButton).button_index).is_equal(BUTTON_RIGHT)

	Input.parse_input_event(InputEventKey.new())
	Input.flush_buffered_events()
	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()
	spy.queue_free()


# O11: con input touch el cursor no se dibuja; el puntero liberado ("mouse libre") y el stick lo
# vuelven a mostrar.
func test_touch_input_hides_the_cursor_but_released_and_stick_show_it() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	cursor.set_desktop_mouse_mode(true, Vector2(120.0, 90.0))
	assert_bool(cursor.is_cursor_visible()).is_true()

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(120.0, 90.0)
	cursor._input(touch)
	assert_bool(cursor._touch_input).is_true()
	assert_bool(cursor.is_cursor_visible()).is_false()

	# Excepcion "mouse libre": el puntero liberado se opera con joypad y debe verse.
	cursor._released = true
	assert_bool(cursor.is_cursor_visible()).is_true()
	cursor._released = false
	assert_bool(cursor.is_cursor_visible()).is_false()

	# Un movimiento de stick lo vuelve a mostrar.
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_0
	motion.axis_value = 0.5
	cursor._input(motion)
	assert_bool(cursor._touch_input).is_false()
	assert_bool(cursor.is_cursor_visible()).is_true()

	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()


# O11: el touch emulado en escritorio llega como motion de mouse REAL; no debe arrastrar el cursor
# ni mostrarlo.
func test_touch_emulated_mouse_motion_keeps_the_cursor_hidden() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	cursor.set_desktop_mouse_mode(true, Vector2(80.0, 80.0))
	MobileUIManager._touch_pointer_until = OS.get_ticks_msec() + 10000

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(200.0, 200.0)
	motion.relative = Vector2(10.0, 0.0)
	cursor._input(motion)

	assert_bool(cursor._touch_input).is_true()
	assert_bool(cursor.is_cursor_visible()).is_false()
	assert_vector2(cursor._position).is_not_equal(motion.position)

	MobileUIManager._touch_pointer_until = 0
	cursor.get_parent().queue_free()


# O11r: el device -1 (mouse que Godot emula por cada dedo) delata el touch aunque MobileUIManager
# no lo haya visto (en modo HUD un control puede consumir el ScreenTouch): el cursor queda oculto.
func test_touch_device_mouse_motion_hides_without_the_mobile_manager_window() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	cursor.set_desktop_mouse_mode(true, Vector2(80.0, 80.0))
	MobileUIManager._touch_pointer_until = 0

	var motion := InputEventMouseMotion.new()
	motion.device = -1
	motion.position = Vector2(200.0, 200.0)
	motion.relative = Vector2(10.0, 0.0)
	cursor._input(motion)

	assert_bool(cursor._touch_input).is_true()
	assert_bool(cursor.is_cursor_visible()).is_false()

	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()


# O11r: el fantasma de device 0 (el X server tambien mueve un puntero real por cada toque) llega
# pegado al evento tactil. Mientras dura la ventana propia no puede limpiar el estado ni mostrar el
# cursor; pasado el plazo, un mouse real vuelve a mandar.
func test_a_phantom_mouse_motion_after_touch_does_not_show_the_cursor() -> void:
	var cursor: Control = VirtualMouseScript.attach_to(self)
	var mouse_mode: int = Input.get_mouse_mode()
	cursor.set_desktop_mouse_mode(true, Vector2(80.0, 80.0))
	MobileUIManager._touch_pointer_until = 0

	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150.0, 120.0)
	cursor._input(drag)
	assert_bool(cursor._touch_input).is_true()

	# El motion del fantasma cae dentro de la ventana propia: no muestra ni mueve el cursor.
	var phantom := InputEventMouseMotion.new()
	phantom.device = 0
	phantom.position = Vector2(400.0, 400.0)
	phantom.relative = Vector2(20.0, 0.0)
	cursor._input(phantom)
	assert_bool(cursor._touch_input).is_true()
	assert_bool(cursor.is_cursor_visible()).is_false()
	assert_vector2(cursor._position).is_not_equal(phantom.position)

	# Vencida la ventana (sin eventos tactiles que la renueven), el mouse real manda de nuevo.
	cursor._touch_input_until = OS.get_ticks_msec() - 1
	cursor._input(phantom)
	assert_bool(cursor._touch_input).is_false()
	assert_bool(cursor.is_cursor_visible()).is_true()
	assert_vector2(cursor._position).is_equal(phantom.position)

	Input.set_mouse_mode(mouse_mode)
	cursor.get_parent().queue_free()

