extends GdUnitTestSuite

# FD-320: el cargador de niveles por datos (MachineLevel) arma escenas desde un layout JSON.
# Esta suite cubre build(), get_item(), export_layout(), save/load y los links con "delay".

const MachineLevel = preload("res://core_v2/props/machines/MachineLevel.gd")

const LAYOUT_PATH := "user://test_machine_level.json"


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "MachineLevelRoot"
	root.translation = Vector3(5000.0, 5000.0, 5000.0)
	get_tree().root.add_child(root)
	return root


func _new_level(root: Node, level_name: String):
	var level = MachineLevel.new()
	level.name = level_name
	root.add_child(level)
	return level


func _settle(frames: int) -> void:
	for _i in range(frames):
		yield(get_tree(), "physics_frame")


func _find_item(items: Array, item_name: String):
	for it in items:
		if str((it as Dictionary).get("name", "")) == item_name:
			return it
	return null


func test_build_creates_block_part_and_hinge() -> void:
	var root := _setup_root()
	var level = _new_level(root, "BuildLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "pos": [0, 0, 0], "size": [1, 1, 1]},
		{"type": "part", "name": "Part", "pos": [2, 0, 0], "size": [2, 1, 3], "density": 100.0},
		{"type": "hinge", "name": "Hinge", "pos": [2, 1, 0], "a": "Part"},
	]})
	var block = level.get_item("Block")
	var part = level.get_item("Part")
	var hinge = level.get_item("Hinge")
	assert_object(block).is_not_null()
	assert_bool(block is StaticBody).is_true()
	assert_object(part).is_not_null()
	assert_object(hinge).is_not_null()
	assert_vector3(part.size).is_equal(Vector3(2, 1, 3))
	assert_float(part.mass).is_equal_approx(600.0, 0.01)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_unknown_item_type_is_ignored() -> void:
	var root := _setup_root()
	var level = _new_level(root, "UnknownLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "size": [1, 1, 1]},
		{"type": "banana", "name": "Weird"},
	]})
	assert_object(level.get_item("Weird")).is_null()
	assert_object(level.get_item("Block")).is_not_null()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_link_with_delay_releases_part() -> void:
	var root := _setup_root()
	var level = _new_level(root, "DelayLevel")
	level.build({"items": [
		{"type": "scene", "name": "Lever", "pos": [0, 0, 0], "path": "res://core_v2/props/controls/LeverV2.tscn"},
		{"type": "part", "name": "Door", "pos": [3, 1, 0], "size": [1, 1, 1], "density": 100.0, "held": true},
		{"type": "link", "from": "Lever", "signal": "activated", "to": "Door", "method": "set_active", "args": [true], "delay": 0.5},
	]})
	var lever = level.get_item("Lever")
	var door = level.get_item("Door")
	assert_object(lever).is_not_null()
	assert_object(door).is_not_null()
	assert_int(door.mode).is_equal(RigidBody.MODE_STATIC)
	lever.interact()
	# Antes de que dispare el link (animacion + delay): sigue retenida.
	yield(_settle(30), "completed")
	assert_int(door.mode).is_equal(RigidBody.MODE_STATIC)
	# Con margen suficiente para animacion + 30 ticks de delay.
	yield(_settle(240), "completed")
	assert_int(door.mode).is_equal(RigidBody.MODE_RIGID)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_layout_round_trip_preserves_items_and_positions() -> void:
	var root := _setup_root()
	var level = _new_level(root, "SaveLevel")
	level.build({"items": [
		{"type": "block", "name": "Block", "pos": [1, 2, 3], "size": [1, 1, 1]},
		{"type": "part", "name": "Part", "pos": [-2, 0.5, 4], "size": [2, 1, 3], "density": 80.0, "held": true},
	]})
	assert_bool(level.save_layout_file(LAYOUT_PATH)).is_true()
	var level2 = _new_level(root, "LoadLevel")
	assert_bool(level2.load_layout_file(LAYOUT_PATH)).is_true()
	for item_name in ["Block", "Part"]:
		var original = level.get_item(item_name)
		var loaded = level2.get_item(item_name)
		assert_object(loaded).is_not_null()
		assert_vector3(loaded.translation).is_equal_approx(original.translation, Vector3(0.01, 0.01, 0.01))
	var dir := Directory.new()
	dir.remove(LAYOUT_PATH)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_export_layout_reflects_moved_piece() -> void:
	var root := _setup_root()
	var level = _new_level(root, "ExportLevel")
	level.build({"items": [
		{"type": "part", "name": "Part", "pos": [0, 0, 0], "size": [1, 1, 1], "density": 100.0, "held": true},
	]})
	var part = level.get_item("Part")
	part.translation = Vector3(7, 8, 9)
	var layout: Dictionary = level.export_layout()
	var moved = _find_item(layout["items"], "Part")
	assert_object(moved).is_not_null()
	assert_float(moved["pos"][0]).is_equal_approx(7.0, 0.01)
	assert_float(moved["pos"][1]).is_equal_approx(8.0, 0.01)
	assert_float(moved["pos"][2]).is_equal_approx(9.0, 0.01)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_cuttable_part_cuts_with_laser_and_fires_link() -> void:
	var root := _setup_root()
	var level = _new_level(root, "CuttableLevel")
	level.build({"items": [
		{"type": "part", "name": "Strut", "pos": [0, 2, 0], "size": [0.4, 1.0, 0.4], "held": true, "cuttable": true, "cut_time": 0.2, "station": 1},
		{"type": "part", "name": "Weight", "pos": [0, 5, 0], "size": [1, 1, 1], "density": 300.0, "held": true, "station": 1},
		{"type": "link", "from": "Strut", "signal": "cut", "to": "Weight", "method": "release"},
	]})
	var strut = level.get_item("Strut")
	var weight = level.get_item("Weight")
	assert_bool(strut.is_cut()).is_false()
	assert_int(weight.mode).is_equal(RigidBody.MODE_STATIC)
	for _i in range(20):
		strut.laser_hit()
		yield(get_tree(), "physics_frame")
	assert_bool(strut.is_cut()).is_true()
	assert_bool(strut.visible).is_false()
	assert_int(weight.mode).is_equal(RigidBody.MODE_RIGID)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_reset_station_restores_cut_and_moved_parts() -> void:
	var root := _setup_root()
	var level = _new_level(root, "ResetLevel")
	level.build({"items": [
		{"type": "part", "name": "Strut", "pos": [0, 2, 0], "size": [0.4, 1.0, 0.4], "held": true, "cuttable": true, "station": 1},
		{"type": "part", "name": "Weight", "pos": [0, 5, 0], "size": [1, 1, 1], "density": 300.0, "held": true, "station": 1},
		{"type": "part", "name": "OtherStationPart", "pos": [4, 1, 0], "size": [1, 1, 1], "held": true, "station": 2},
		{"type": "link", "from": "Strut", "signal": "cut", "to": "Weight", "method": "release"},
	]})
	var strut = level.get_item("Strut")
	var weight = level.get_item("Weight")
	var other = level.get_item("OtherStationPart")
	strut.cut_now()
	other.translation = Vector3(10, 10, 10)
	yield(_settle(20), "completed")
	assert_bool(strut.is_cut()).is_true()
	assert_float(weight.translation.y).is_less(4.8)
	level.reset_station(1)
	assert_bool(strut.is_cut()).is_false()
	assert_bool(strut.visible).is_true()
	assert_int(weight.mode).is_equal(RigidBody.MODE_STATIC)
	assert_vector3(weight.translation).is_equal_approx(Vector3(0, 5, 0), Vector3(0.02, 0.02, 0.02))
	# La estacion 2 no se toca al resetear la estacion 1.
	assert_vector3(other.translation).is_equal_approx(Vector3(10, 10, 10), Vector3(0.02, 0.02, 0.02))
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_multitool_grab_moves_rigid_part() -> void:
	var root := _setup_root()
	var level = _new_level(root, "GrabLevel")
	level.build({"items": [
		{"type": "block", "name": "Floor", "pos": [0, -0.5, 0], "size": [12, 1, 12]},
		{"type": "part", "name": "Cargo", "pos": [0, 0.6, -2.5], "size": [0.8, 0.8, 0.8], "density": 150.0},
	]})
	var mt_scene := load("res://core_v2/player/MultiToolV2.tscn") as PackedScene
	var mt = mt_scene.instance()
	root.add_child(mt)
	mt.translation = Vector3(0, 1.2, 0)
	yield(_settle(5), "completed")
	var cargo: RigidBody = level.get_item("Cargo")
	mt.current_mode = mt.Mode.GRAB
	assert_bool(mt.grab_body(cargo, 2.5)).is_true()
	# Girar la herramienta hacia +X (mirando hacia +X => basis.z apunta a -X)
	mt.transform = Transform(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 1.5, 0))
	var InputDataV2 = load("res://core_v2/input/InputDataV2.gd")
	var input = InputDataV2.new()
	input.tool_fire_primary = true
	for _i in range(40):
		mt.step(1.0 / 60.0, input)
		yield(get_tree(), "physics_frame")
	assert_float(cargo.translation.x).is_greater(1.5)
	mt.release_grab()
	assert_object(mt.get_grabbed_body()).is_null()
	root.queue_free()
	yield(get_tree(), "idle_frame")


# Avance manual: los retardos deben conservar exactamente sus ticks al restaurar.
func test_snapshot_pending_uses_names_and_restores_into_new_level() -> void:
	var root := _setup_root()
	var source = _new_level(root, "SnapshotSource")
	var target = _new_level(root, "SnapshotTarget")
	var layout: Dictionary = {"items": [
		{"type": "part", "name": "Door", "held": true},
	]}
	source.build(layout)
	target.build(layout)
	source.set_physics_process(false)
	target.set_physics_process(false)
	var args: Array = [true]
	source._on_link_fired(source.get_item("Door"), "set_active", args, 4, "Switch")
	source._on_link_fired(source, "reset_station", [99], 6, "Switch")
	source._physics_process(1.0 / 60.0)
	source._ringhub_return_state = {"wakeup": {"wakeup_completed": true}, "player_snapshot": {"yaw": 0.7}}
	var snapshot: Dictionary = source.get_snapshot()
	var pending: Array = snapshot.get("pending", [])
	assert_int(pending.size()).is_equal(2)
	if pending.size() == 2:
		assert_str(pending[0][1]).is_equal("Door")
		assert_str(pending[1][1]).is_equal("@level")
	args[0] = false # El snapshot no comparte argumentos con la cola viva.
	target.restore_snapshot(snapshot)
	assert_bool(target._ringhub_return_state["wakeup"]["wakeup_completed"]).is_true()
	source._ringhub_return_state["player_snapshot"]["yaw"] = 2.0
	assert_float(target._ringhub_return_state["player_snapshot"]["yaw"]).is_equal(0.7)
	for _i in range(2):
		target._physics_process(1.0 / 60.0)
	assert_bool(target.get_item("Door").held).is_true()
	target._physics_process(1.0 / 60.0)
	assert_bool(target.get_item("Door").held).is_false()
	assert_bool(source.get_item("Door").held).is_true()
	for _i in range(2):
		target._physics_process(1.0 / 60.0)
	assert_int(target.get_station_resets()).is_equal(1)
	assert_int(source.get_station_resets()).is_equal(0)
	if pending.size() == 2:
		assert_int(pending[0][0]).is_equal(3) # Restaurar tampoco comparte la cola guardada.
		assert_bool(pending[0][3][0]).is_true()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_restore_legacy_snapshot_clears_pending_and_transient_feedback() -> void:
	var root := _setup_root()
	var level = _new_level(root, "LegacySnapshot")
	level.build({"items": [{"type": "part", "name": "Door", "held": true}]})
	level.set_physics_process(false)
	level._on_link_fired(level.get_item("Door"), "release", [], 1)
	level._subtitle_queue.append(["obsolete", 8.0])
	level._subtitle_hold_ticks = 20
	level._last_countdown_sec = 3
	level._void_kill_cooldown_ticks = 200
	level._conduits.append({"active_ticks": 50})
	level.restore_snapshot({"elapsed_ticks": 7})
	assert_int(level._pending.size()).is_equal(0)
	assert_int(level._subtitle_queue.size()).is_equal(0)
	assert_int(level._subtitle_hold_ticks).is_equal(0)
	assert_int(level._last_countdown_sec).is_equal(-1)
	assert_int(level._void_kill_cooldown_ticks).is_equal(0)
	assert_int(level._conduits[0]["active_ticks"]).is_equal(0)
	level._physics_process(1.0 / 60.0)
	assert_bool(level.get_item("Door").held).is_true()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_hinge_snapshot_restores_motor_and_joint_parameters() -> void:
	var root := _setup_root()
	var level = _new_level(root, "HingeSnapshot")
	level.build({"items": [
		{"type": "part", "name": "Part", "held": true},
		{"type": "hinge", "name": "Hinge", "a": "Part", "axle": false,
		 "motor": {"on": true, "speed": 3.0, "torque": 120.0}},
	]})
	yield(get_tree(), "idle_frame")
	var hinge = level.get_item("Hinge")
	assert_bool(hinge.is_in_group("replay_sync")).is_true()
	assert_bool(hinge.has_method("get_snapshot")).is_true()
	if hinge.has_method("get_snapshot"):
		var snapshot: Dictionary = hinge.get_snapshot()
		hinge.set_active(false)
		hinge.motor_speed = 9.0
		hinge.motor_torque = 8.0
		hinge.restore_snapshot(snapshot)
		assert_bool(hinge.motor_enabled).is_true()
		assert_float(hinge.motor_speed).is_equal(3.0)
		assert_float(hinge.motor_torque).is_equal(120.0)
		assert_bool(hinge._joint.get_flag(HingeJoint.FLAG_ENABLE_MOTOR)).is_true()
		assert_float(hinge._joint.get_param(HingeJoint.PARAM_MOTOR_TARGET_VELOCITY)).is_equal(3.0)
		assert_float(hinge._joint.get_param(HingeJoint.PARAM_MOTOR_MAX_IMPULSE)).is_equal(120.0)
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_trigger_snapshot_restores_one_shot_state() -> void:
	var root := _setup_root()
	var level = _new_level(root, "TriggerSnapshot")
	level.build({"items": [{"type": "trigger", "name": "Entry"}]})
	var trigger = level.get_item("Entry")
	assert_bool(trigger.is_in_group("replay_sync")).is_true()
	assert_bool(trigger.has_method("get_snapshot")).is_true()
	if trigger.has_method("get_snapshot"):
		var snapshot: Dictionary = trigger.get_snapshot()
		trigger._fired = true
		trigger.restore_snapshot(snapshot)
		assert_bool(trigger._fired).is_false()
		trigger._fired = true
		snapshot = trigger.get_snapshot()
		trigger._fired = false
		trigger.restore_snapshot(snapshot)
		assert_bool(trigger._fired).is_true()
	root.queue_free()
	yield(get_tree(), "idle_frame")


func test_reset_station_cancels_own_level_links_only() -> void:
	var root := _setup_root()
	var level = _new_level(root, "ResetPending")
	level.build({"items": [
		{"type": "trigger", "name": "EntryOne", "station": 1},
		{"type": "trigger", "name": "EntryTwo", "station": 2},
	]})
	level.set_physics_process(false)
	level._on_link_fired(level, "say", ["station one"], 5, "EntryOne")
	level._on_link_fired(level, "say", ["station two"], 5, "EntryTwo")
	level._on_link_fired(level, "say", ["global"], 5)
	level.reset_station(1)
	assert_int(level._pending.size()).is_equal(2)
	if level._pending.size() == 2:
		assert_str(level._pending[0][5]).is_equal("EntryTwo")
	level.reset_station()
	assert_int(level._pending.size()).is_equal(0)
	root.queue_free()
	yield(get_tree(), "idle_frame")
