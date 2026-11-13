extends GdUnitTestSuite

# Momentos cinematograficos del Vertical Slice.
#
# Dos "momentos clave" de la Bahia de Maquinas implementados con la infraestructura
# existente (CameraZone + CinematicRig + CinematicManager), sin un segundo sistema:
#   1. Llegada / descenso a la Bahia (Cinematics/ArrivalGate).
#   2. Puente sobre el fuego en la Estacion 5 (Cinematics/BridgeFireGate).
#
# Verifica el wiring y el contrato de inmersion: al entrar el CinematicManager activa
# el rig; al salir devuelve el control al jugador (rig liberado, modo FREE) sin quedar
# pegado.

const BayScene := preload("res://core_v2/levels/machines/MachineBay.tscn")
const VirtualMouseScript := preload("res://core_v2/ui/VirtualMouse.gd")

const SETTLE_TICKS := 30
const SHOT_TICKS := 120

var _scene: Node = null
var _pilot: KinematicBody = null
var _previous_scene: Node = null
var _saved_state: Array = []


func after_test() -> void:
	VirtualMouseScript.set_pointer_released(false)


func _cm() -> Node:
	return get_node_or_null("/root/CinematicManager")


func _rig_of(gate: Node) -> Node:
	return gate.get_node_or_null(gate.get("cinematic_rig_path"))


func _save_state() -> void:
	_saved_state = []
	var session: Node = get_node("/root/SessionManager")
	var teleport: Node = session.get_node("TeleportSystem")
	for spec in [
		[session, ["player", "is_respawning", "_oys_input_override"]],
		[teleport, ["player_controller", "camera_controller", "initial_spawn_transform"]]
	]:
		for key in spec[1]:
			var value = spec[0].get(key)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			_saved_state.append([spec[0], key, value])


func _restore_state() -> void:
	for entry in _saved_state:
		entry[0].set(entry[1], entry[2])
	_saved_state = []


func _teardown() -> void:
	if is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	_pilot = null
	yield(get_tree(), "idle_frame")
	if is_instance_valid(_previous_scene):
		get_tree().current_scene = _previous_scene
	_restore_state()
	var cm = _cm()
	if cm and cm.has_method("reset"):
		cm.reset()


func _boot() -> void:
	_previous_scene = get_tree().current_scene
	_save_state()
	var session: Node = get_node("/root/SessionManager")
	var teleport: Node = session.get_node("TeleportSystem")
	_scene = BayScene.instance()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_pilot = _scene.get_node("Pilot")
	session.player = _pilot
	teleport.player_controller = _pilot
	teleport.camera_controller = _pilot.get_node("CameraRig")
	VirtualMouseScript.set_pointer_released(false)
	if _pilot.input_provider:
		_pilot.input_provider.set_live_mode()
		_pilot.input_provider.hardware_input_enabled = false


func _assert_moment_frames_forward(gate_path: String, forward_min_z: float, gate_min_z: float) -> void:
	var bay = auto_free(BayScene.instance())
	add_child(bay)
	yield(get_tree(), "idle_frame")
	var gate = bay.get_node_or_null(gate_path)
	assert_object(gate).is_not_null()
	assert_bool(gate.is_in_group("CameraZoneV2")).is_true()
	var rig = _rig_of(gate)
	assert_object(rig).is_not_null()
	var cam: Camera = rig.get_node_or_null("Camera")
	assert_object(cam).is_not_null()
	var forward: Vector3 = -cam.global_transform.basis.z
	assert_float(forward.z).is_greater(forward_min_z)
	assert_float(gate.global_transform.origin.z).is_greater(gate_min_z)


# ---------------------------------------------------------------------------
# Wiring: cada momento expone una CameraZone con rig y un encuadre hacia la accion.
# ---------------------------------------------------------------------------

func test_arrival_moment_frames_the_bay_depth() -> void:
	yield(_assert_moment_frames_forward("Cinematics/ArrivalGate", 0.9, 7.0), "completed")


func test_bridge_fire_moment_frames_the_burning_bridge() -> void:
	yield(_assert_moment_frames_forward("Cinematics/BridgeFireGate", 0.9, 78.0), "completed")


# ---------------------------------------------------------------------------
# Integracion: cada zona activa su rig y, al salir, el control vuelve al jugador.
# ---------------------------------------------------------------------------

func test_cinematic_zones_activate_rigs_then_return_control() -> void:
	_boot()
	for _i in range(SETTLE_TICKS):
		yield(get_tree(), "physics_frame")
	var cm = _cm()
	assert_object(cm).is_not_null()
	assert_bool(cm.is_active()).is_false()
	for gate_name in ["ArrivalGate", "BridgeFireGate"]:
		var gate = _scene.get_node("Cinematics/" + gate_name)
		var rig = _rig_of(gate)
		assert_object(rig).is_not_null()
		# Entrar en la zona del momento clave.
		_pilot.global_transform.origin = gate.global_transform.origin + Vector3(0.0, -1.5, 0.0)
		_pilot.velocity = Vector3.ZERO
		var activated := false
		for _i in range(SHOT_TICKS):
			yield(get_tree(), "physics_frame")
			if cm.active_rig == rig:
				activated = true
				break
		assert_bool(activated).is_true()
		assert_bool(cm.is_active()).is_true()
		assert_object(cm.get_active_camera()).is_not_null()
		# Salir: el control vuelve al jugador (rig liberado, modo FREE), sin quedar pegado.
		_pilot.global_transform.origin = Vector3(0.0, 1.0, -5.0)
		_pilot.velocity = Vector3.ZERO
		var released := false
		for _i in range(SHOT_TICKS):
			yield(get_tree(), "physics_frame")
			if not cm.is_active():
				released = true
				break
		assert_bool(released).is_true()
		assert_int(cm.get_control_mode()).is_equal(cm.ControlMode.FREE)
	yield(_teardown(), "completed")
