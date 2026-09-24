extends GdUnitTestSuite

# FD-307 B1/B2: la capsula como interactuable de cuerpo entero y la camara de la accion
# de escotilla operada desde la GUI.

const CriopodScene = preload("res://core_v2/props/criopod/Criopod_vert.tscn")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")
const SCREEN_ID := "ship:cryopod:elias"

var _mounted_nodes: Array = []
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _previous_tree_paused: bool = false
var _requests_before: Dictionary = {}

func before_test() -> void:
	_mounted_nodes.clear()
	_previous_mouse_mode = Input.get_mouse_mode()
	_previous_tree_paused = get_tree().paused
	get_tree().paused = false
	SuitOS.close_hud_mode()
	SuitOS.unregister_screen(SCREEN_ID)
	VirtualMouseScript.set_pointer_released(false)
	_requests_before = CinematicManager._active_requests.duplicate()

func after_test() -> void:
	for node in _mounted_nodes:
		if is_instance_valid(node):
			node.free()
	_mounted_nodes.clear()
	for id in CinematicManager._active_requests.keys():
		if not _requests_before.has(id):
			CinematicManager.release_camera_request(id)
	SuitOS.close_hud_mode()
	SuitOS.unregister_screen(SCREEN_ID)
	VirtualMouseScript.set_pointer_released(false)
	Input.set_mouse_mode(_previous_mouse_mode)
	get_tree().paused = _previous_tree_paused

func _mount(scene: PackedScene) -> Node:
	var node = scene.instance()
	get_tree().root.add_child(node)
	_mounted_nodes.append(node)
	return node

func _drop(node: Node) -> void:
	_mounted_nodes.erase(node)
	if is_instance_valid(node):
		node.free()

func _has_watch_request_for(rig: Node) -> bool:
	for id in CinematicManager._active_requests.keys():
		if _requests_before.has(id):
			continue
		var req = CinematicManager._active_requests[id]
		if req.payload.get("rig", null) == rig:
			return true
	return false

# B1: el area interactuable del pod tiene que alcanzar la carcasa (DisplayCaseBody), no solo
# la caja chica pegada al vidrio, y resolver al terminal. Se sondean la tapa, el fondo y los
# laterales de la capsula, donde el collider viejo (extents z 0.55) no llegaba.
func test_pod_interaction_area_covers_the_capsule_and_resolves_to_the_terminal() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "physics_frame")
	var terminal = pod.get_node("RotatingObjectV2/CryoPodTerminal")
	var entity: Area = terminal.get_node("InteractableEntity")
	var shape_node: CollisionShape = entity.get_node("CollisionShape")
	var xf: Transform = shape_node.global_transform
	var extents: Vector3 = shape_node.shape.extents
	var inverse: Transform = xf.affine_inverse()

	# La resolucion del jugador (_resolve_interactable_root) camina hacia arriba desde el
	# area hasta un nodo interactuable: tiene que ser el terminal.
	var resolved: Node = null
	var current: Node = entity
	while current != null:
		if current.get("is_interactable") != null and bool(current.get("is_interactable")) and current.has_method("interact"):
			resolved = current
			break
		current = current.get_parent()

	var probes := {
		"fondo": Vector3(0.0, 0.6, -0.7),
		"frente": Vector3(0.0, 0.6, 0.6),
		"izquierda": Vector3(-0.7, 0.6, 0.0),
		"derecha": Vector3(0.7, 0.6, 0.0),
		"tapa": Vector3(0.0, 2.3, 0.0),
		"piso": Vector3(0.0, 0.1, 0.0),
	}
	for label in probes.keys():
		var local: Vector3 = inverse.xform(pod.to_global(probes[label]))
		var inside: bool = abs(local.x) <= extents.x and abs(local.y) <= extents.y and abs(local.z) <= extents.z
		assert_bool(inside).override_failure_message(
			"el area interactuable no cubre %s del pod (local=%s extents=%s)" % [label, local, extents]).is_true()

	assert_object(resolved).is_same(terminal)
	assert_bool(terminal.is_in_group("interactable")).is_true()

	_drop(pod)
	yield (get_tree(), "idle_frame")

# B2: abrir desde la GUI pide el FocusedRig del pod por CinematicManager y lo libera cuando
# la escotilla termina de animar.
func test_hatch_action_requests_and_releases_the_focus_camera() -> void:
	var pod = _mount(CriopodScene)
	yield (get_tree(), "physics_frame")
	var hatch = pod.get_node("RotatingObjectV2")
	var terminal = pod.get_node("RotatingObjectV2/CryoPodTerminal")
	var hudable = terminal.get_node("CryoPodHUDable")
	var focused_rig = terminal.get_node("CinematicSetup/FocusedRig")

	var result: Dictionary = hudable.perform_action("toggle_hatch")
	assert_bool(bool(result.get("ok", false))).override_failure_message("la accion no abrio la escotilla").is_true()

	for _i in range(6):
		yield (get_tree(), "physics_frame")
		if _has_watch_request_for(focused_rig):
			break
	assert_bool(_has_watch_request_for(focused_rig)).override_failure_message("no se pidio la camara de foco al abrir").is_true()

	# Terminar la animacion inmediatamente: el pedido de camara tiene que soltarse.
	hatch.set_active(true, true)
	for _i in range(6):
		yield (get_tree(), "physics_frame")
		if not _has_watch_request_for(focused_rig):
			break
	assert_bool(_has_watch_request_for(focused_rig)).override_failure_message("la camara de foco no se libero al terminar la animacion").is_false()

	_drop(pod)
	yield (get_tree(), "idle_frame")
