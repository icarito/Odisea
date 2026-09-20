extends GdUnitTestSuite

# FD-307: la criocapsula como pantalla de OdiseaOS.
# Cubre lo que se rompio a mano en esta feature: el cursor del modo Pantalla del HUD
# (mapeo absoluto vs relativo) y la escotilla operada desde la UI en vez de a mano.

const CryoPodTerminalScene = preload("res://core_v2/props/criopod/CryoPodTerminal.tscn")
const CriopodScene = preload("res://core_v2/props/criopod/Criopod_vert.tscn")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")
const SCREEN_ID := "ship:cryopod:elias"

var _mounted_nodes: Array = []
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE

func before_test() -> void:
	_mounted_nodes.clear()
	_previous_mouse_mode = Input.get_mouse_mode()
	SuitOS.close_hud_mode()
	SuitOS.unregister_screen(SCREEN_ID)
	VirtualMouseScript.set_pointer_released(false)
	_clear_virtual_mice()

func after_test() -> void:
	for node in _mounted_nodes:
		if is_instance_valid(node):
			node.free()
	_mounted_nodes.clear()
	SuitOS.close_hud_mode()
	SuitOS.unregister_screen(SCREEN_ID)
	VirtualMouseScript.set_pointer_released(false)
	_clear_virtual_mice()
	Input.set_mouse_mode(_previous_mouse_mode)

func _mount(scene: PackedScene) -> Node:
	var node = scene.instance()
	get_tree().root.add_child(node)
	_mounted_nodes.append(node)
	return node

func _drop(node: Node) -> void:
	_mounted_nodes.erase(node)
	if is_instance_valid(node):
		node.free()

func _clear_virtual_mice() -> void:
	for node in get_tree().get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(node) and is_instance_valid(node.get_parent()):
			node.get_parent().free()

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

func test_cryo_pod_ui_button_opens_hatch() -> void:
	var pod = _mount(CriopodScene)
	var hatch = pod.get_node("RotatingObjectV2")
	var ui = pod.get_node("RotatingObjectV2/CryoPodTerminal/Viewport/CryoPodUI")
	var button = ui.get_node("HatchButton")

	assert_str(String(ui.get("_screen_id"))).is_equal("ship:cryopod:elias")
	assert_bool(button.disabled).is_false()
	button.emit_signal("pressed")
	assert_bool(hatch.is_active).is_true()

	_drop(pod)
	yield (get_tree(), "idle_frame")

func test_cryo_pod_ui_viewport_click_opens_hatch() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "idle_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var terminal = pod.get_node("RotatingObjectV2/CryoPodTerminal")
	var viewport = terminal.get_node("Viewport")
	var button = viewport.get_node("CryoPodUI/HatchButton")

	terminal._is_focused = true
	terminal._update_ui_mode()
	var cursor: Vector2 = viewport.get("_cursor_position")
	var target: Vector2 = button.get_global_rect().position + button.rect_size * 0.5
	viewport.process_mouse_motion(target - cursor)
	viewport.process_mouse_click(BUTTON_LEFT, true)
	viewport.process_mouse_click(BUTTON_LEFT, false)
	assert_bool(hatch.is_active).is_true()

	_drop(pod)
	yield (get_tree(), "idle_frame")

func test_terminal_turns_off_on_open_and_is_interactable_again_on_close() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "idle_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var terminal = pod.get_node("RotatingObjectV2/CryoPodTerminal")
	var hudable = pod.get_node("RotatingObjectV2/CryoPodTerminal/CryoPodHUDable")
	var button: Button = terminal.get_node("Viewport/CryoPodUI/HatchButton")
	var previous_mouse_mode: int = Input.get_mouse_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var mouse_mode_is_settable: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	VirtualMouseScript.set_pointer_released(true)

	assert_bool(terminal.is_interactable).is_true()
	var opened: Dictionary = hudable.perform_action("toggle_hatch")
	assert_bool(bool(opened.get("hatch_open", false))).is_true()
	assert_bool(terminal.is_active).is_false()
	assert_bool(terminal.is_interactable).is_true()
	assert_bool(terminal.is_focusable).is_true()
	assert_bool(button.disabled).is_true()
	assert_bool(bool(hudable.hud_gamepad_actions()[0].enabled)).is_false()
	assert_bool(bool(hudable.perform_action("toggle_hatch").get("ok", true))).is_false()
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	assert_bool(VirtualMouseScript.is_pointer_released()).is_false()
	if mouse_mode_is_settable:
		assert_int(Input.get_mouse_mode()).is_equal(Input.MOUSE_MODE_CAPTURED)

	# El cierre real puede ocurrir mucho despues; aca comprobamos el contrato de estado,
	# no un timeout dependiente de cuantos frames alcance a procesar CI.
	yield (get_tree(), "physics_frame")
	hatch.set_active(false, true)
	yield (get_tree(), "physics_frame")
	assert_bool(hatch.is_active).is_false()
	assert_bool(terminal.is_active).is_false()
	assert_bool(terminal.is_interactable).is_true()
	assert_bool(terminal.is_focusable).is_true()
	assert_bool(button.disabled).is_false()
	assert_bool(bool(hudable.hud_gamepad_actions()[0].enabled)).is_true()

	var player := Spatial.new()
	get_tree().root.add_child(player)
	player.add_to_group("player")
	player.global_transform.origin = terminal.get_node("CinematicSetup/FocusedRig").global_transform.origin
	assert_bool(terminal._pick_focus_rig() == null).is_true()
	terminal.interact()
	assert_bool(terminal.is_active).is_true()
	assert_bool(terminal._is_focused).is_true()

	_drop(player)
	_drop(pod)
	yield (get_tree(), "idle_frame")
	VirtualMouseScript.set_pointer_released(false)
	Input.set_mouse_mode(previous_mouse_mode)

func test_glass_shell_collides_with_player_layer() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "physics_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var colliders: Array = []
	for child in hatch.get_children():
		if child is CollisionShape and child.shape != null:
			colliders.append(child)

	assert_int(hatch.collision_layer & 64).is_equal(64)
	assert_int(colliders.size()).is_equal(6)
	var terminal = hatch.get_node("CryoPodTerminal")
	var from: Vector3 = hatch.to_global(Vector3(0.0, 0.72, 0.0))
	var to: Vector3 = hatch.to_global(Vector3(0.7, 0.72, 0.0))
	var hit: Dictionary = pod.get_world().direct_space_state.intersect_ray(from, to, [terminal], 64)
	assert_object(hit["collider"]).is_same(hatch)

	_drop(pod)
	yield (get_tree(), "idle_frame")

func test_first_hatch_open_rotates_glass_with_collisions_enabled() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "physics_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var closed_basis: Basis = hatch.global_transform.basis
	var colliders: Array = []
	for child in hatch.get_children():
		if child is CollisionShape and child.shape != null:
			colliders.append(child)

	for collider in colliders:
		assert_bool(collider.disabled).is_false()
	hatch.set_active(true)
	yield (get_tree(), "physics_frame")
	assert_float(float(hatch.anim_progress)).is_greater(0.0)
	for collider in colliders:
		assert_bool(collider.disabled).is_false()
	assert_bool(hatch.global_transform.basis.is_equal_approx(closed_basis)).is_false()

	hatch.set_active(false)
	yield (get_tree(), "physics_frame")
	for collider in colliders:
		assert_bool(collider.disabled).is_false()

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

func test_elias_pod_keeps_ringhub_slot_scale() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "idle_frame")
	var mesh: MeshInstance = pod as MeshInstance

	assert_vector3(mesh.scale).is_equal(Vector3.ONE * 1.5)

	_drop(pod)
	yield (get_tree(), "idle_frame")
