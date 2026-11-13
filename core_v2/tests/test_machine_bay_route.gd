extends GdUnitTestSuite

# FD-320 (regresion publica): recorrido de ENTRADA de la bahia de maquinas con el piloto real.
#
# A diferencia de los casos balisticos por estacion (que apagan checkpoints y killzones y
# teletransportan al piloto), este test arranca en el spawn de la escena, deja checkpoints y
# killzones ACTIVOS, y camina con input publico hasta la aproximacion de la Estacion 1.
#
# Contrato de input: se conduce el InputProviderV2 real de `InputProviderV2._read_live_input()`
# accionando las acciones del InputMap (move_forward/backward/left/right) que el proveedor lee
# cada tick; el proveedor empaqueta ese input en un InputDataV2 que el PlayerControllerV2
# consume. No se teletransporta al destino ni se escriben velocidades privadas: el unico
# estado que el test fija es el spawn inicial, que ya define la escena.

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")

# Aproximacion de la Estacion 1: la palanca que libera el contrapeso del balancin.
const STATION1_LEVER := Vector3(1.6, 0.0, 4.6)
const APPROACH_RADIUS := 1.4
const MAX_TICKS := 900
const SETTLE_TICKS := 30
const CHECK_ENTRY_BASE := Vector3(0.0, 1.0, 1.0)
const MOVE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]

var _bay: Node = null
var _pilot: KinematicBody = null
var _previous_scene: Node = null
var _saved_state: Array = []
var _test_directory: String = ""
var _debug_trace := false


func after_test() -> void:
	_release_move_actions()
	VirtualMouseScript.set_pointer_released(false)


# ---------------------------------------------------------------------------
# Input publico (InputProviderV2 -> acciones del InputMap)
# ---------------------------------------------------------------------------

func _release_move_actions() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


# Pulsa las acciones de movimiento que llevan al piloto hacia `target`, usando la MISMA base de
# camara que consume PlayerControllerV2._get_move_direction (CinematicManager.get_movement_basis)
# en vez de asumir la convencion de ejes del rig.
func _drive_toward(pilot: Spatial, target: Vector3) -> void:
	var origin: Vector3 = pilot.global_transform.origin
	var to_target: Vector3 = target - origin
	to_target.y = 0.0
	if to_target.length() < 0.01:
		_release_move_actions()
		return
	var desired: Vector3 = to_target.normalized()
	var basis: Basis = _movement_basis(pilot)
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd_component: float = desired.dot(forward)
	var right_component: float = desired.dot(right)
	_set_move_actions(fwd_component, right_component)


func _set_move_actions(fwd_component: float, right_component: float) -> void:
	_release_move_actions()
	if fwd_component > 0.05:
		Input.action_press("move_forward", clamp(fwd_component, 0.0, 1.0))
	elif fwd_component < -0.05:
		Input.action_press("move_backward", clamp(-fwd_component, 0.0, 1.0))
	if right_component > 0.05:
		Input.action_press("move_right", clamp(right_component, 0.0, 1.0))
	elif right_component < -0.05:
		Input.action_press("move_left", clamp(-right_component, 0.0, 1.0))


# Base de movimiento efectiva: la camara activa (identica fuente que _get_move_direction en modo
# FREE). Si no hay camara activa se cae a la camara del viewport y, en ultimo caso, a identidad.
func _movement_basis(pilot: Spatial) -> Basis:
	var cinematic: Node = get_node_or_null("/root/CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var active: Camera = cinematic.get_active_camera()
		if active != null and is_instance_valid(active):
			return active.global_transform.basis
	var viewport: Viewport = pilot.get_viewport()
	if viewport != null:
		var vp_camera: Camera = viewport.get_camera()
		if vp_camera != null and is_instance_valid(vp_camera):
			return vp_camera.global_transform.basis
	return Basis.IDENTITY


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Aislamiento de estado (no tocar saves reales del jugador)
# ---------------------------------------------------------------------------

func _save_autoload_state() -> void:
	_saved_state = []
	var persistence: Node = get_node("/root/PersistenceManager")
	var session: Node = get_node("/root/SessionManager")
	var checkpoints: Node = get_node("/root/CheckpointManager")
	var teleport: Node = session.get_node("TeleportSystem")
	for spec in [
		[persistence, ["checkpoint_directory", "checkpoint_resource", "_continue_requested", "registered_entities", "_scene_hash_cache"]],
		[session, ["player", "is_respawning", "_oys_input_override"]],
		[teleport, ["player_controller", "camera_controller", "initial_spawn_transform"]],
		[checkpoints, ["active_checkpoint_pos", "active_checkpoint_yaw", "active_checkpoint_pitch", "active_replay_snapshot", "default_respawn_position", "default_respawn_yaw", "default_respawn_pitch", "default_replay_snapshot", "_default_snapshot_scene_id", "_default_snapshot_ice_path"]]
	]:
		for key in spec[1]:
			var value = spec[0].get(key)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			_saved_state.append([spec[0], key, value])


func _restore_autoload_state() -> void:
	for entry in _saved_state:
		entry[0].set(entry[1], entry[2])
	_saved_state = []


func _remove_directory(path: String) -> void:
	var directory := Directory.new()
	if directory.open(path) == OK:
		directory.list_dir_begin(true, true)
		var filename: String = directory.get_next()
		while filename != "":
			directory.remove(filename)
			filename = directory.get_next()
		directory.list_dir_end()
	Directory.new().remove(path)


# ---------------------------------------------------------------------------
# Bare de la escena
# ---------------------------------------------------------------------------

func _item(item_name: String) -> Node:
	return _bay.get_node("Level").get_item(item_name)


func _teardown() -> void:
	_release_move_actions()
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null
	_pilot = null
	yield(get_tree(), "idle_frame")
	if is_instance_valid(_previous_scene):
		get_tree().current_scene = _previous_scene
	_restore_autoload_state()
	_remove_directory(_test_directory)


# ---------------------------------------------------------------------------
# Test: entrada -> aproximacion Estacion 1 con input publico, checkpoints/killzones activos.
# ---------------------------------------------------------------------------

func test_entry_walk_reaches_station1_approach_with_active_zones() -> void:
	var tree: SceneTree = get_tree()
	_previous_scene = tree.current_scene
	_save_autoload_state()
	# Este segmento usa el esquema FREE sin latch; otros modos requieren otra ruta.
	var cinematic: Node = get_node("/root/CinematicManager")
	assert_int(cinematic.get_control_mode()).is_equal(cinematic.ControlMode.FREE)
	assert_bool(cinematic.is_input_latched()).is_false()

	# Directorio de checkpoints aislado: toda escritura de campana queda contenida.
	var persistence: Node = get_node("/root/PersistenceManager")
	var session: Node = get_node("/root/SessionManager")
	var checkpoints: Node = get_node("/root/CheckpointManager")
	var teleport: Node = session.get_node("TeleportSystem")
	_test_directory = "user://test_machine_bay_route_%s" % OS.get_ticks_usec()
	persistence.checkpoint_directory = _test_directory
	persistence.checkpoint_resource = null
	persistence._continue_requested = false

	# Escena real, escena actual para que el TeleportSystem resuelva esta bahia, y piloto
	# registrado para que checkpoints/killzones operen como en juego.
	_bay = BayScene.instance()
	tree.root.add_child(_bay)
	tree.current_scene = _bay
	_pilot = _bay.get_node("Pilot")
	session.player = _pilot
	teleport.player_controller = _pilot
	teleport.camera_controller = _pilot.get_node("CameraRig")
	VirtualMouseScript.set_pointer_released(false)
	if _pilot.input_provider:
		_pilot.input_provider.set_live_mode()
		_pilot.input_provider.hardware_input_enabled = true

	for _i in range(SETTLE_TICKS):
		yield(tree, "physics_frame")

	# Checkpoints y killzones DEBEN quedar activos (no se desactivan como en los casos balisticos).
	var check_entry: Node = _item("CheckEntry")
	var kill_floor: Node = _item("KillFloor")
	var check_entry_active: bool = is_instance_valid(check_entry) and check_entry.is_inside_tree() \
		and not check_entry.is_queued_for_deletion() and bool(check_entry.get("monitoring"))
	var kill_floor_active: bool = is_instance_valid(kill_floor) and kill_floor.is_inside_tree() \
		and not kill_floor.is_queued_for_deletion() and bool(kill_floor.get("monitoring"))

	# Recorrido real desde el spawn de entrada hasta la aproximacion de la Estacion 1.
	var start_pos: Vector3 = _pilot.global_transform.origin
	var start_id: int = _pilot.get_instance_id()
	var start_hdist: float = _horizontal_distance(start_pos, STATION1_LEVER)
	var last_pos: Vector3 = start_pos
	var min_y: float = start_pos.y
	var reached: bool = false
	var ticks: int = 0
	while ticks < MAX_TICKS and is_instance_valid(_pilot):
		var pos: Vector3 = _pilot.global_transform.origin
		last_pos = pos
		min_y = min(min_y, pos.y)
		if _horizontal_distance(pos, STATION1_LEVER) <= APPROACH_RADIUS:
			reached = true
			break
		_drive_toward(_pilot, STATION1_LEVER)
		yield(tree, "physics_frame")
		ticks += 1
	_release_move_actions()

	var alive: bool = is_instance_valid(_pilot)
	var end_pos: Vector3 = _pilot.global_transform.origin if alive else last_pos
	var end_id: int = _pilot.get_instance_id() if alive else -1
	var end_on_floor: bool = alive and _pilot.is_on_floor()
	var end_hdist: float = _horizontal_distance(end_pos, STATION1_LEVER)

	# Checkpoint de entrada: caminar por la zona debe activarlo (checkpoints activos de verdad).
	var cp_pos_raw = checkpoints.get("active_checkpoint_pos")
	var cp_pos: Vector3 = cp_pos_raw if cp_pos_raw is Vector3 else Vector3(9999.0, 9999.0, 9999.0)
	var checkpoint_fired: bool = cp_pos.distance_to(CHECK_ENTRY_BASE) < 0.3
	var checkpoint_slot_saved: bool = false
	var checkpoint_resource: Resource = persistence.get_checkpoint_resource(_bay.filename)
	if checkpoint_resource != null:
		var slots = checkpoint_resource.get("slots")
		if slots is Dictionary:
			checkpoint_slot_saved = slots.has("last")

	if _debug_trace:
		prints("[machine_bay_route] ticks", ticks, "reached", reached, "start", start_pos, "end", end_pos,
			"floor", end_on_floor, "checkpoint", cp_pos, "slot", checkpoint_slot_saved)

	# Devolver el entorno ANTES de afirmar: un fallo no debe filtrar estado compartido.
	yield(_teardown(), "completed")

	assert_bool(alive).is_true()
	assert_bool(reached).is_true()
	assert_bool(end_on_floor).is_true()
	assert_int(end_id).is_equal(start_id)
	# Recorrido real por input, no un salto: exige una cantidad no trivial de ticks de fisica.
	assert_int(ticks).is_greater(20)
	# Nunca cayo bajo el piso de entrada (KillFloor esta muy por debajo del piso caminable).
	assert_float(min_y).is_greater(-0.5)
	# Progreso real hacia la Estacion 1 desde el spawn de entrada.
	assert_float(start_hdist - end_hdist).is_greater(4.0)
	assert_float(end_pos.z - start_pos.z).is_greater(3.0)
	# Llegada segura: sobre el piso de entrada, sin caer al KillFloor ni salir volando.
	assert_float(end_pos.y).is_greater(-0.5)
	assert_float(end_pos.y).is_less(2.0)
	assert_float(abs(end_pos.x)).is_less(7.0)
	assert_float(end_pos.z).is_greater(-7.0)
	assert_float(end_pos.z).is_less(16.0)
	# Checkpoints y killzones siguen activos y el checkpoint de entrada se disparo.
	assert_bool(check_entry_active).is_true()
	assert_bool(kill_floor_active).is_true()
	assert_bool(checkpoint_fired or checkpoint_slot_saved).is_true()
