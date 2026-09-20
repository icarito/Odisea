extends GdUnitTestSuite

# FD-307: la criocapsula como pantalla de OdiseaOS.
# Cubre lo que se rompio a mano en esta feature: el cursor del modo Pantalla del HUD
# (mapeo absoluto vs relativo) y la escotilla operada desde la UI en vez de a mano.

const CryoPodTerminalScene = preload("res://core_v2/props/criopod/CryoPodTerminal.tscn")
const CriopodScene = preload("res://core_v2/props/criopod/Criopod_vert.tscn")

func _mount(scene: PackedScene) -> Node:
	var node = scene.instance()
	get_tree().root.add_child(node)
	return node

func _drop(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()

# El HUD dibuja este Viewport en el mesh del presentador, que no ocupa la ventana: el
# mapeo absoluto del puntero cae donde no es y deja el cursor clavado. Mientras dure el
# prestamo el cursor tiene que ser el del Viewport, movido por delta.
func test_borrowed_viewport_forces_relative_cursor() -> void:
	var terminal = _mount(CryoPodTerminalScene)
	yield (get_tree(), "idle_frame")
	var viewport = terminal.get_node("Viewport")
	var hudable = terminal.get_node("CryoPodHUDable")

	assert_bool(viewport.forces_relative_cursor()).is_false()

	hudable.borrow_viewport()
	assert_bool(viewport.forces_relative_cursor()).is_true()
	assert_bool(terminal._wants_system_mouse()).is_false()

	# Nadie puede devolverlo al mouse del sistema mientras el HUD lo tenga prestado.
	viewport.set_use_system_mouse(true)
	assert_bool(terminal._wants_system_mouse()).is_false()

	hudable.release_viewport()
	assert_bool(viewport.forces_relative_cursor()).is_false()

	_drop(terminal)
	yield (get_tree(), "idle_frame")

func test_relative_cursor_moves_with_mouse_delta() -> void:
	var terminal = _mount(CryoPodTerminalScene)
	yield (get_tree(), "idle_frame")
	var viewport = terminal.get_node("Viewport")
	viewport.set_ui_mode(true)
	terminal.get_node("CryoPodHUDable").borrow_viewport()

	var before: Vector2 = viewport.get("_cursor_position")
	viewport.process_mouse_motion(Vector2(60.0, -25.0))
	var after: Vector2 = viewport.get("_cursor_position")

	assert_vector2(after).is_not_equal(before)

	_drop(terminal)
	yield (get_tree(), "idle_frame")

# La escotilla dejo de ser un interactuable suelto: la opera la holoterminal.
func test_hatch_is_not_a_loose_interactable_and_opens_from_the_screen() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "idle_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var hudable = pod.get_node("RotatingObjectV2/CryoPodTerminal/CryoPodHUDable")

	assert_bool(hatch.is_interactable).is_false()
	assert_bool(hatch.is_in_group("interactable")).is_false()
	assert_bool(hatch.is_active).is_false()

	var result: Dictionary = hudable.perform_action("toggle_hatch")
	assert_bool(bool(result.get("ok", false))).is_true()
	assert_bool(hatch.is_active).is_true()
	assert_bool(bool(hudable.widget_snapshot().get("hatch_open", false))).is_true()

	_drop(pod)
	yield (get_tree(), "idle_frame")

# El interactuable del pod es uno solo y cubre la capsula, no una caja pegada al vidrio.
func test_pod_has_a_single_interactable_covering_the_capsule() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "idle_frame")

	var found: Array = []
	for node in get_tree().get_nodes_in_group("interactable"):
		if pod.is_a_parent_of(node):
			found.append(node)

	assert_int(found.size()).is_equal(1)
	assert_str(found[0].name).is_equal("CryoPodTerminal")
	var extents: Vector3 = found[0].get_node("CollisionShape").shape.extents
	assert_float(extents.y).is_greater(1.0)

	_drop(pod)
	yield (get_tree(), "idle_frame")
