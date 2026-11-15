extends GdUnitTestSuite

# Transit-Run Pista B2: verifica que MachineBay tiene una ruta principal continua
# de parkour (calibrada al 70-80% del alcance: H_max~3.6m, D_max~10m), sin puzles
# obligatorios, y que las 5 estaciones funcionan como Side Sockets opcionales con
# recompensa cinética determinista.

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const FlowRouteValidatorScript = preload("res://core_v2/systems/flow/FlowRouteValidator.gd")
const MOVE_ACTIONS := ["move_forward", "move_backward", "move_left", "move_right", "jump", "run"]

var _bay: Node = null


func after_test() -> void:
	_release_actions()


func before() -> void:
	_bay = BayScene.instance()
	get_tree().root.add_child(_bay)
	for zone in get_tree().get_nodes_in_group("CheckZoneV2"):
		if _bay.is_a_parent_of(zone):
			zone.queue_free()
	for kzone in get_tree().get_nodes_in_group("KillZoneV2"):
		if _bay.is_a_parent_of(kzone):
			kzone.queue_free()


func after() -> void:
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null
	yield(get_tree(), "idle_frame")


func _item(item_name: String) -> Node:
	return _bay.get_node("Level").get_item(item_name)


func _top_y(block_name: String) -> float:
	var body: StaticBody = _item(block_name) as StaticBody
	var shape: CollisionShape = body.get_child(0) as CollisionShape
	var box: BoxShape = shape.shape as BoxShape
	return body.global_transform.origin.y + box.extents.y


func test_parkour_main_route_platforms_exist_and_stay_within_jump_budget() -> void:
	# Altura máxima real ~3.57m (70-80% => <= 2.85m por salto).
	var max_step_height := 2.85
	var sequence := [
		["EntryFloor", "ParkourEntryStep"],
		["ParkourEntryStep", "Ledge1"],
		["Dock1", "ParkourStep2A"],
		["ParkourStep2A", "ParkourStep2B"],
		["ParkourStep2B", "Dock2"],
		["Ledge2", "ParkourClimb3A"],
		["ParkourClimb3A", "ParkourClimb3B"],
		["ParkourClimb3B", "ParkourClimb3C"],
		["ParkourClimb3C", "ParkourClimb3D"],
		["ParkourClimb3D", "Ledge3"],
		["Ledge3", "ParkourStep4A"],
		["ParkourStep4A", "Station5Deck"],
		["Station5Deck", "ParkourStep5A"],
		["ParkourStep5A", "ParkourStep5B"],
		["ParkourStep5B", "Landing5B"],
	]
	for pair in sequence:
		var a: Node = _item(pair[0])
		var b: Node = _item(pair[1])
		assert_object(a).is_not_null()
		assert_object(b).is_not_null()
		var dy: float = _top_y(pair[1]) - _top_y(pair[0])
		assert_float(dy).is_less_equal(max_step_height)


func test_side_sockets_start_inactive_and_activate_on_station_trigger() -> void:
	var triggers := [
		["SeesawStrut", "cut", "BoostSocket1"],
		["PendulumLatch", "cut", "BoostSocket2"],
		["StrutHeavy", "cut", "BoostSocket3"],
		["CentrifugeJam", "cut", "BoostSocket4"],
		["BridgeValveCut", "activated", "BoostSocket5"],
	]
	for spec in triggers:
		var pad: Area = _item(spec[2]) as Area
		assert_object(pad).is_not_null()
		assert_bool(pad.is_boost_active()).is_false()
		var source: Node = _item(spec[0])
		assert_object(source).is_not_null()
		source.emit_signal(spec[1])
		assert_bool(pad.is_boost_active()).is_true()


func test_boost_socket_applies_deterministic_kinetic_impulse_and_snapshot() -> void:
	var pad: Area = _item("BoostSocket1") as Area
	var pilot: KinematicBody = _bay.get_node("Pilot")
	pad.set_active(true)
	var snap: Dictionary = pad.save_snapshot()
	assert_bool(bool(snap.get("is_active", false))).is_true()
	pilot.global_transform.origin = pad.global_transform.origin + Vector3(0.0, 0.5, 0.0)
	pilot.velocity = Vector3.ZERO
	for _i in range(6):
		yield(get_tree(), "physics_frame")
	assert_float(pilot.velocity.y).is_greater(5.0)
	assert_float(pilot.velocity.z).is_greater(5.0)
	pad.set_active(false)
	assert_bool(pad.is_boost_active()).is_false()
	pad.restore_snapshot(snap)
	assert_bool(pad.is_boost_active()).is_true()


func test_labyrinth_streamer_flow_validator_hook_is_safe_without_flow_system() -> void:
	var streamer = _bay.get_node_or_null("MachineBayLabyrinthStreamer")
	assert_object(streamer).is_not_null()
	var res: Dictionary = streamer.validate_seed_with_flow_validator(20261114)
	assert_bool(res.has("seed")).is_true()
	assert_bool(bool(res.get("valid", false))).is_true()


func test_main_route_passes_flow_route_validator_within_80_percent_threshold() -> void:
	var node_names := [
		"EntryFloor", "ParkourEntryStep", "Ledge1", "Dock1StepA", "Dock1StepB", "Dock1",
		"ParkourStep2A", "ParkourStep2B", "Dock2", "Ledge2",
		"ParkourClimb3A", "ParkourClimb3B", "ParkourClimb3C", "ParkourClimb3D", "Ledge3",
		"ParkourStep4A", "Station5Deck", "ParkourStep5A", "ParkourStep5B", "Landing5B",
		"TowerRamp", "ExitPad",
	]
	var nodes := []
	for n in node_names:
		var body: StaticBody = _item(n) as StaticBody
		assert_object(body).is_not_null()
		var shape: CollisionShape = body.get_child(0) as CollisionShape
		var box: BoxShape = shape.shape as BoxShape
		var top_pos: Vector3 = body.global_transform.origin + Vector3(0.0, box.extents.y, 0.0)
		nodes.append({"id": n, "pos": top_pos, "size": box.extents * 2.0})
	var edges := []
	for i in range(node_names.size() - 1):
		if node_names[i] == "TowerRamp" and node_names[i + 1] == "ExitPad":
			# Conexión caminable continua mediante TowerAscendRamp (inclinada 39°).
			edges.append({"from": "TowerRamp", "to": "ExitPad", "gap_h": 0.0, "delta_h": 0.0})
		else:
			edges.append({"from": node_names[i], "to": node_names[i + 1]})
	var fm = FlowMetricsScript.from_scene()
	assert_object(fm).is_not_null()
	var raw: Dictionary = fm.metrics()
	var metrics := {
		"g": float(raw["gravity"]),
		"v_run": float(raw["run_speed"]),
		"v_jump": float(raw["jump_force"]),
		"tick": 1.0 / float(raw["tick_hz"]),
		"main_threshold": float(raw["thr_main_max_ratio"]),
	}
	var report: Dictionary = FlowRouteValidatorScript.validate(
		{"entry": "EntryFloor", "exit": "ExitPad", "nodes": nodes, "edges": edges},
		metrics
	)
	assert_bool(bool(report.get("valid_main_route", false))).is_true()


func _release_actions() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func _drive_toward(pilot: Spatial, target: Vector3) -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(action)
	var to_target: Vector3 = target - pilot.global_transform.origin
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return
	var desired: Vector3 = to_target.normalized()
	var basis: Basis = Basis.IDENTITY
	var cinematic: Node = get_node_or_null("/root/CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var active: Camera = cinematic.get_active_camera()
		if active != null and is_instance_valid(active):
			basis = active.global_transform.basis
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


func test_full_parkour_traversal_entry_to_exit_without_machines() -> void:
	var pilot: KinematicBody = _bay.get_node("Pilot")
	pilot.input_provider.set_live_mode()
	pilot.input_provider.hardware_input_enabled = true
	var cinematic: Node = get_node_or_null("/root/CinematicManager")

	# Waypoints [pos_destino, saltar_al_acercarse, radio_llegada, (opcional) jump_dist]
	var waypoints := [
		[Vector3(-4.2, 0.0, 6.8), false, 1.0],
		[Vector3(-4.2, 1.25, 9.2), true, 1.1, 2.0],
		[Vector3(-4.2, 2.5, 13.0), true, 1.2, 2.5],
		[Vector3(-1.5, 2.5, 15.2), false, 1.0],
		[Vector3(-1.5, 3.7, 17.0), true, 1.0, 1.8],
		[Vector3(-1.5, 4.9, 19.0), true, 1.0, 1.8],
		[Vector3(-1.2, 6.0, 20.8), true, 1.0, 1.8],
		[Vector3(-2.7, 6.0, 21.6), false, 0.9],
		[Vector3(-4.5, 6.0, 26.5), true, 1.4, 5.5],
		[Vector3(-4.5, 5.9, 32.2), true, 1.4, 4.5],
		[Vector3(-2.5, 5.6, 37.7), true, 1.3, 4.5],
		[Vector3(-5.5, 3.5, 41.5), false, 1.2],
		[Vector3(-7.5, 5.65, 43.0), true, 1.3, 2.5],
		[Vector3(-7.5, 7.85, 48.2), true, 1.3, 4.5],
		[Vector3(-7.5, 10.05, 53.4), true, 1.3, 4.5],
		[Vector3(-6.5, 12.25, 58.0), true, 1.3, 4.5],
		[Vector3(-4.8, 13.0, 62.5), true, 1.3, 4.0],
		[Vector3(-7.2, 11.65, 71.0), true, 1.4, 7.8],
		[Vector3(-4.5, 10.0, 78.2), true, 1.4, 6.0],
		[Vector3(4.8, 10.0, 89.0), false, 1.1],
		[Vector3(4.8, 10.9, 92.4), true, 1.3, 3.0],
		[Vector3(4.8, 10.9, 98.0), true, 1.3, 4.5],
		[Vector3(2.2, 10.0, 103.0), true, 1.4, 4.5],
		[Vector3(2.2, 10.4, 111.5), false, 1.3],
		[Vector3(2.2, 22.0, 129.0), false, 1.8],
	]

	for i in range(waypoints.size()):
		var wp = waypoints[i]
		var target: Vector3 = wp[0]
		var should_jump: bool = bool(wp[1])
		var radius: float = float(wp[2])
		var jump_dist: float = float(wp[3]) if wp.size() > 3 else 3.0
		var jump_cooldown := 0
		var reached := false
		for _tick in range(360):
			if not is_instance_valid(pilot):
				break
			if cinematic != null:
				assert_int(cinematic.get_control_mode()).is_equal(cinematic.ControlMode.FREE)
				assert_bool(cinematic.is_input_latched()).is_false()
			var cur_pos: Vector3 = pilot.global_transform.origin
			var dist_xz := Vector2(cur_pos.x - target.x, cur_pos.z - target.z).length()
			if not pilot.is_on_floor() and dist_xz <= 0.7:
				for action in ["move_forward", "move_backward", "move_left", "move_right", "run"]:
					Input.action_release(action)
			else:
				_drive_toward(pilot, target)
				if not should_jump or jump_dist > 3.0 or dist_xz > jump_dist + 0.5:
					Input.action_press("run")
				else:
					Input.action_release("run")
			if should_jump and pilot.is_on_floor() and jump_cooldown == 0 and dist_xz <= jump_dist:
				Input.action_press("jump")
				jump_cooldown = 18
			else:
				Input.action_release("jump")
			if jump_cooldown > 0:
				jump_cooldown -= 1
			yield(get_tree(), "physics_frame")
			if not is_instance_valid(pilot):
				break
			var pos: Vector3 = pilot.global_transform.origin
			var horiz := Vector2(pos.x - target.x, pos.z - target.z).length()
			if horiz <= radius and pos.y >= target.y - 0.6 and pilot.is_on_floor():
				reached = true
				break
		_release_actions()
		if not reached:
			prints("[parkour_traversal] FAILED at wp", i, target, "pilot_valid=", is_instance_valid(pilot), "pos=", pilot.global_transform.origin if is_instance_valid(pilot) else Vector3.ZERO)
			assert_bool(reached).is_true()
			break
		assert_bool(reached).is_true()

	assert_float(pilot.global_transform.origin.z).is_greater_equal(127.0)
	assert_float(pilot.global_transform.origin.y).is_greater_equal(21.5)
