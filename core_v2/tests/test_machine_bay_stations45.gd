extends GdUnitTestSuite

# FD-320 (rescate estaciones 4/5): verificacion focalizada del fix minimo 2026-11-13.
#
#  Estacion 4 - LEGIBILIDAD: el rotor queda como estaba (test balistico ya lo cubre); se
#    simplifica el cartel y se saca la pieza suelta BridgeExtension. Aca se confirma que el
#    circuito palanca -> traba -> motor sigue cableado sobre la escena completa.
#  Estacion 5 - SOLVABILIDAD: la palanca del puente basculante no bajaba (bisagra con limite
#    incompatible + motor nunca habilitado) y el contrapeso de torre caia al vacio. El rescate
#    la reduce a UNA accion (valvula) mas un trayecto caminable: puente fijo + rampa estatica
#    hasta el ExitPad. Aca se conduce al piloto con INPUT publico desde Station5Deck al exit.

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")
const MOVE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right"]

var _bay: Node = null
var _pilot: KinematicBody = null


func after_test() -> void:
	_release_actions()


func _release_actions() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _item(item_name: String) -> Node:
	return _bay.get_node("Level").get_item(item_name)


func _fmt(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _load_bay(pilot_pos: Vector3) -> void:
	_bay = BayScene.instance()
	_pilot = _bay.get_node("Pilot")
	_pilot.translation = pilot_pos
	get_tree().root.add_child(_bay)
	# Aislar de checkpoints/killzones: aca la bahia cuelga de root, no es current_scene.
	for zone in get_tree().get_nodes_in_group("CheckZoneV2"):
		if _bay.is_a_parent_of(zone):
			zone.queue_free()
	for kzone in get_tree().get_nodes_in_group("KillZoneV2"):
		if _bay.is_a_parent_of(kzone):
			kzone.queue_free()
	_pilot.input_provider.set_live_mode()
	_pilot.input_provider.hardware_input_enabled = true


func _free_bay() -> void:
	_release_actions()
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null
	_pilot = null
	yield(get_tree(), "idle_frame")


func _settle(ticks: int) -> void:
	for _i in range(ticks):
		yield(get_tree(), "physics_frame")


func _basis(pilot: Spatial) -> Basis:
	var cinematic: Node = get_node_or_null("/root/CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var active: Camera = cinematic.get_active_camera()
		if active != null and is_instance_valid(active):
			return active.global_transform.basis
	return Basis.IDENTITY


# Conduce con las acciones del InputMap hacia `target` (solo direccion horizontal).
func _drive_toward(pilot: Spatial, target: Vector3) -> void:
	_release_actions()
	var to_target: Vector3 = target - pilot.global_transform.origin
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return
	var desired: Vector3 = to_target.normalized()
	var basis: Basis = _basis(pilot)
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = basis.x
	right.y = 0.0
	right = right.normalized()
	var fwd: float = desired.dot(forward)
	var rgt: float = desired.dot(right)
	if fwd > 0.05:
		Input.action_press("move_forward", clamp(fwd, 0.0, 1.0))
	elif fwd < -0.05:
		Input.action_press("move_backward", clamp(-fwd, 0.0, 1.0))
	if rgt > 0.05:
		Input.action_press("move_right", clamp(rgt, 0.0, 1.0))
	elif rgt < -0.05:
		Input.action_press("move_left", clamp(-rgt, 0.0, 1.0))


# --- Estacion 4: el rotor sigue cableado (palanca -> traba -> motor) y el cartel es claro ---
func test_station4_rotor_still_wired_and_sign_reads() -> void:
	_load_bay(Vector3(0, 13.5, 60.0))
	yield(_settle(30), "completed")
	assert_bool(_item("BridgeExtension") == null).is_true()
	assert_str(String(_item("SignStation4").get("text"))).contains("ESTACIÓN 4")
	var motor: Node = _item("CentrifugeHinge")
	var ips: int = Engine.iterations_per_second
	_item("CentrifugeLever").interact()
	_item("CentrifugeLever").step(2.0)
	yield(_settle(int(round(3.5 * ips)) + 4), "completed")
	assert_bool(_item("CentrifugeJam").is_cut()).is_true()
	assert_bool(motor.motor_enabled).is_false()
	yield(_settle(int(round(1.5 * ips)) + 4), "completed")
	assert_bool(motor.motor_enabled).is_true()
	yield(_free_bay(), "completed")


# --- Estacion 5: valvula + trayecto caminable hasta el ExitPad, con input real ---
func test_station5_valve_clears_fire_and_path_reaches_exit() -> void:
	_load_bay(Vector3(0, 10.5, 84.0))
	yield(_settle(40), "completed")
	# La valvula es la accion unica: corta todo el plasma del trayecto (puente y torre).
	_item("BridgeValveCut").interact()
	yield(_settle(40), "completed")
	assert_bool(bool(_item("BridgeFlameL").get("is_active"))).is_false()
	assert_bool(bool(_item("BridgeFlameR").get("is_active"))).is_false()
	assert_bool(bool(_item("TowerFlame1").get("is_active"))).is_false()
	# El puente es una plataforma caminable (no una bisagra que se traba).
	var walk: Spatial = _item("DrawbridgeDeck")
	assert_float(walk.global_transform.origin.z).is_between(90.0, 100.0)
	# Recorrido real: muelle -> puente -> Landing5B -> rampa estatica -> ExitPad.
	var reached := false
	var max_y: float = _pilot.global_transform.origin.y
	for _i in range(2100):
		var p: Vector3 = _pilot.global_transform.origin
		# Waypoint rodante alineado con la rampa (x=2.2) que empuja siempre +Z.
		var target: Vector3 = Vector3(2.2, 22, max(p.z + 6.0, 120.0))
		_drive_toward(_pilot, target)
		yield(get_tree(), "physics_frame")
		p = _pilot.global_transform.origin
		max_y = max(max_y, p.y)
		if p.z > 127.4 and p.y > 21.0 and p.y < 23.0 and abs(p.x) < 14.0 and _pilot.is_on_floor():
			reached = true
			break
	_release_actions()
	prints("[st45] station5 end", _fmt(_pilot.global_transform.origin), "max_y", "%.2f" % max_y)
	assert_bool(reached).is_true()
	yield(_free_bay(), "completed")
