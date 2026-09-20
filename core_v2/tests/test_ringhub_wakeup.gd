extends GdUnitTestSuite

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")


func test_opening_cryo_pod_does_not_move_pilot() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: Spatial = level.get_node("Pilot")
	yield(get_tree(), "idle_frame")

	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	# El spawn queda unos centimetros sobre WakeupFloor y la fisica lo asienta. Lo que
	# debe permanecer inmovil es la posicion ya asentada mientras gira el vidrio.
	for _i in range(30):
		yield(get_tree(), "physics_frame")
	var before: Transform = pilot.global_transform

	hatch.set_active(true)
	for _i in range(210):
		yield(get_tree(), "physics_frame")

	assert_bool(bool(hatch.is_active)).is_true()
	# CI corre toda la suite en un solo proceso gdunit; a esta altura ya arrastra huerfanos y
	# carga de otras suites, que sacude el asentamiento un poco mas que en una corrida aislada
	# (medido en CI: ~0.019). El margen es sobre eso, no sobre lo que se ve en local.
	assert_float(pilot.global_transform.origin.distance_to(before.origin)).is_less(0.05)
	assert_bool(pilot.global_transform.basis.is_equal_approx(before.basis)).is_true()


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
	yield(get_tree(), "idle_frame")

	var pilot_shape: CollisionShape = pilot.get_node("CollisionShape")
	for _i in range(30):
		yield(get_tree(), "physics_frame")
	var pod: Spatial = level.get_node("Criopod_Vert")
	var local_origin: Vector3 = pod.to_local(pilot.global_transform.origin)
	# Ver comentario en test_opening_cryo_pod_does_not_move_pilot: margen sobre lo observado
	# en CI (~0.68), no sobre el asentamiento de una corrida local aislada.
	assert_float(abs(local_origin.x)).is_less(0.9)
	assert_float(abs(local_origin.z)).is_less(0.9)
	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(pilot_shape.shape)
	params.transform = pilot_shape.global_transform
	params.collision_mask = 255
	params.exclude = [pilot]
	var hits: Array = pilot.get_world().direct_space_state.intersect_shape(params, 32)

	for hit in hits:
		var collider = hit.get("collider", null)
		if collider != null and pod.is_a_parent_of(collider) \
				and collider != level.get_node("Criopod_Vert/WakeupFloor"):
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
