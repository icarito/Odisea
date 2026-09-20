extends GdUnitTestSuite

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")


func test_opening_cryo_pod_does_not_move_pilot() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: Spatial = level.get_node("Pilot")
	var before: Transform = pilot.global_transform
	yield(get_tree(), "idle_frame")

	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	for _i in range(5):
		yield(get_tree(), "physics_frame")
	assert_bool(pilot.global_transform.is_equal_approx(before)).is_true()

	hatch.set_active(true)
	for _i in range(210):
		yield(get_tree(), "physics_frame")

	assert_bool(bool(hatch.is_active)).is_true()
	assert_bool(pilot.global_transform.is_equal_approx(before)).is_true()


func test_ringhub_cryopod_ui_button_opens_hatch() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")

	var hatch = level.get_node("Criopod_Vert/RotatingObjectV2")
	var ui = level.get_node("Criopod_Vert/RotatingObjectV2/CryoPodTerminal/Viewport/CryoPodUI")
	var button = ui.get_node("HatchButton")

	assert_bool(button.disabled).is_false()
	button.emit_signal("pressed")
	assert_bool(hatch.is_active).is_true()


func test_ringhub_open_pod_hatch_does_not_toggle_an_open_hatch() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")

	var hatch = level.get_node("Criopod_Vert/RotatingObjectV2")
	hatch.set_active(true)
	level.open_pod_hatch()

	assert_bool(hatch.is_active).is_true()


func test_initial_screen_close_releases_wakeup_once_without_open_button() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")

	var hatch = level.get_node("Criopod_Vert/RotatingObjectV2")
	var zone = level.get_node("Criopod_Vert/CinematicSequence")
	var script_file: String = String(zone.script_file)
	level._gate_wakeup_sequence()

	assert_bool(hatch.is_active).is_false()
	assert_str(String(zone.script_file)).is_empty()
	level._on_pod_screen_closed(level.pod_screen_id)
	assert_str(String(zone.script_file)).is_equal(script_file)
	assert_str(String(level._gated_oys_script)).is_empty()

	zone.script_file = ""
	level._on_pod_screen_closed(level.pod_screen_id)
	assert_str(String(zone.script_file)).is_empty()


func test_pilot_capsule_starts_inside_pod_without_collision_overlap() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: KinematicBody = level.get_node("Pilot")
	var initial: Transform = pilot.global_transform
	yield(get_tree(), "idle_frame")

	var pilot_shape: CollisionShape = pilot.get_node("CollisionShape")
	yield(get_tree(), "physics_frame")
	assert_bool(pilot.global_transform.is_equal_approx(initial)).is_true()
	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(pilot_shape.shape)
	params.transform = pilot_shape.global_transform
	params.collision_mask = 255
	params.exclude = [pilot]
	var hits: Array = pilot.get_world().direct_space_state.intersect_shape(params, 32)

	for hit in hits:
		var collider = hit.get("collider", null)
		if collider != null and level.get_node("Criopod_Vert").is_a_parent_of(collider):
			assert_bool(false).is_true()

	assert_int(level.get_node("Criopod_Vert/StaticBody").collision_layer & 1).is_equal(1)
	assert_int(level.get_node("Criopod_Vert/StaticBody2").collision_layer & 1).is_equal(1)
	assert_int(level.get_node("Criopod_Vert/WakeupFloor").collision_layer & 1).is_equal(1)

	for path in ["StaticBody", "StaticBody2", "RotatingObjectV2"]:
		var body: Node = level.get_node("Criopod_Vert/" + path)
		for child in body.get_children():
			if child is CollisionShape:
				assert_bool(child.disabled).is_false()


func test_pod_body_blocks_camera_with_environment_layer() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "physics_frame")

	var pilot: KinematicBody = level.get_node("Pilot")
	var spring_arm: Spatial = pilot.get_node("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm")
	var from: Vector3 = spring_arm.global_transform.origin
	var direction: Vector3 = spring_arm.global_transform.basis.z.normalized()
	var hit: Dictionary = pilot.get_world().direct_space_state.intersect_ray(
		from, from + direction * 3.0, [pilot], 1)

	assert_int(spring_arm.collision_mask & 1).is_equal(1)
	assert_bool(not hit.empty()).is_true()


func test_open_hatch_leaves_exit_corridor_clear() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "physics_frame")

	var pilot: KinematicBody = level.get_node("Pilot")
	var pod: Spatial = level.get_node("Criopod_Vert")
	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	hatch.set_active(true)
	for _i in range(210):
		yield(get_tree(), "physics_frame")

	var origin := pilot.global_transform.origin + pod.global_transform.basis.y.normalized() * 0.75
	var exit_direction := pod.global_transform.basis.z.normalized()
	var hit: Dictionary = pilot.get_world().direct_space_state.intersect_ray(
		origin, origin + exit_direction * 1.5, [pilot], 79)

	assert_bool(hit.empty()).is_true()
