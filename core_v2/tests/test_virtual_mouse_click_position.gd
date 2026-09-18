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
	cursor._emit_event(click)

	assert_int(spy.seen.size()).is_equal(1)
	# Por SceneTree.input_event() aca llegaba _position reescalada por viewport/ventana.
	assert_vector2(spy.seen[0]).is_equal(cursor._position)

	cursor.get_parent().queue_free()
	spy.queue_free()

func test_attach_to_reuses_the_existing_cursor() -> void:
	var first: Control = VirtualMouseScript.attach_to(self)
	var second: Control = VirtualMouseScript.attach_to(self)

	assert_object(second).is_same(first)
	assert_int(get_tree().get_nodes_in_group("virtual_mouse").size()).is_equal(1)

	first.get_parent().queue_free()

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
	assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_HIDDEN)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(280.0, 180.0)
	cursor._input(motion)
	assert_vector2(cursor._position).is_equal(motion.position)
	cursor.set_desktop_mouse_mode(false)
	assert_int(Input.get_mouse_mode()).is_equal(mouse_mode)
	cursor.get_parent().queue_free()
