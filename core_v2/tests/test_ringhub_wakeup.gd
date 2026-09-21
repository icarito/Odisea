extends GdUnitTestSuite

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")
const CriopodScene = preload("res://core_v2/props/criopod/Criopod_vert.tscn")


func _wait_until_pilot_settles(pilot: Spatial) -> void:
	var stable_frames: int = 0
	for _i in range(180):
		yield(get_tree(), "physics_frame")
		var speed: float = (pilot.velocity as Vector3).length() if "velocity" in pilot else 0.0
		stable_frames = stable_frames + 1 if speed < 0.05 else 0
		if stable_frames >= 5:
			return


func _disable_pilot_input(pilot: Spatial) -> void:
	if "input_provider" in pilot and pilot.input_provider != null:
		pilot.input_provider.hardware_input_enabled = false


# Cuanto se corre el piloto respecto del pod en N ticks, sin que pase nada. Es el control
# del A/B: _wait_until_pilot_settles() acepta hasta 0.05 m/s como "quieto", asi que en una
# maquina lenta el piloto sigue reptando varios centimetros por su cuenta durante la ventana
# que dura la puerta. Medir eso aparte es la unica forma de afirmar que la puerta no lo
# empujo, en vez de afirmar un numero absoluto que depende de la maquina.
func _drift_over(pilot: Spatial, pod: Spatial, frames: int) -> float:
	var start: Vector3 = (pod.global_transform.affine_inverse() * pilot.global_transform).origin
	for _i in range(frames):
		yield(get_tree(), "physics_frame")
	var end: Vector3 = (pod.global_transform.affine_inverse() * pilot.global_transform).origin
	return start.distance_to(end)


func _hatch_window(hatch: Node) -> int:
	return int(ceil(float(hatch.anim_duration) * Engine.iterations_per_second)) + 30


func _wait_until_hatch_stops(hatch: Node) -> void:
	var max_frames: int = int(ceil(float(hatch.anim_duration) * Engine.iterations_per_second)) + 30
	for _i in range(max_frames):
		yield(get_tree(), "physics_frame")
		if abs(float(hatch.anim_progress) - float(hatch.target_progress)) <= 0.001:
			return


func test_opening_cryo_pod_does_not_move_pilot() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: Spatial = level.get_node("Pilot")
	_disable_pilot_input(pilot)
	yield(get_tree(), "idle_frame")

	var pod: Spatial = level.get_node("Criopod_Vert")
	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	# No mirar velocity antes del primer paso: el Pilot nace en cero aunque todavia no haya
	# resuelto el piso. Exigimos varios frames estables antes de medir el efecto de la puerta.
	yield(_wait_until_pilot_settles(pilot), "completed")

	# A/B: primero cuanto deriva el piloto SOLO, en la misma ventana que va a durar la puerta.
	var window: int = _hatch_window(hatch)
	var baseline = yield(_drift_over(pilot, pod, window), "completed")

	var before: Transform = pod.global_transform.affine_inverse() * pilot.global_transform
	hatch.set_active(true)
	yield(_wait_until_hatch_stops(hatch), "completed")

	assert_bool(bool(hatch.is_active)).is_true()
	var after: Transform = pod.global_transform.affine_inverse() * pilot.global_transform
	var moved: float = after.origin.distance_to(before.origin)
	# Lo que se afirma es que la PUERTA no lo empuja, no que el piloto este congelado: se le
	# permite la misma deriva que ya tenia sin que pasara nada, mas un margen.
	assert_float(moved).override_failure_message(
		"la puerta movio al piloto %.4f m, con una deriva propia de %.4f m" % [moved, baseline]
	).is_less(baseline + 0.05)
	assert_bool(after.basis.is_equal_approx(before.basis)).is_true()


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


func test_wakeup_keeps_pilot_collision_mask() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "idle_frame")

	var pilot: PhysicsBody = level.get_node("Pilot")
	var initial_mask: int = pilot.collision_mask
	level._gate_wakeup_sequence()
	level._release_wakeup_sequence()
	assert_int(pilot.collision_mask).is_equal(initial_mask)


func test_pilot_capsule_starts_inside_pod_without_collision_overlap() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: KinematicBody = level.get_node("Pilot")
	_disable_pilot_input(pilot)
	yield(get_tree(), "idle_frame")

	var pilot_shape: CollisionShape = pilot.get_node("CollisionShape")
	yield(_wait_until_pilot_settles(pilot), "completed")
	var pod: Spatial = level.get_node("Criopod_Vert")
	var local_origin: Vector3 = pod.to_local(pilot.global_transform.origin)
	# Ver comentario en test_opening_cryo_pod_does_not_move_pilot: margen sobre lo observado
	# en CI (~0.68), no sobre el asentamiento de una corrida local aislada.
	assert_float(abs(local_origin.x)).is_less(0.1)
	assert_float(abs(local_origin.z)).is_less(0.1)
	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(pilot_shape.shape)
	params.transform = pilot_shape.global_transform
	# El chequeo usa el mask real del Pilot; RingHubWakeup no puede alterarlo.
	params.collision_mask = pilot.collision_mask
	params.exclude = [pilot]
	var hits: Array = pilot.get_world().direct_space_state.intersect_shape(params, 32)

	for hit in hits:
		var collider = hit.get("collider", null)
		if collider != null and pod.is_a_parent_of(collider):
			assert_bool(false).override_failure_message(
				"Pilot solapa %s" % String(collider.get_path())).is_true()

	assert_int(level.get_node("Criopod_Vert/DisplayCaseBody").collision_layer & 1).is_equal(1)
	var glass_shapes: Array = []
	for child in level.get_node("Criopod_Vert/RotatingObjectV2").get_children():
		if child is CollisionShape:
			glass_shapes.append(child)
	assert_int(glass_shapes.size()).is_equal(3)
	for glass_shape in glass_shapes:
		assert_bool(glass_shape.shape is BoxShape).is_true()

	for path in ["DisplayCaseBody", "RotatingObjectV2"]:
		var body: Node = level.get_node("Criopod_Vert/" + path)
		for child in body.get_children():
			if child is CollisionShape:
				assert_bool(child.disabled).is_false()


func test_wakeup_slot_has_no_decorative_criopod_collision() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	var pilot: Spatial = level.get_node("Pilot")
	_disable_pilot_input(pilot)
	var chunk: Node = level.get_node("ScaffoldStreamRoot/Chunk_Criopods")
	for _i in range(180):
		if chunk.is_chunk_loaded():
			break
		yield(get_tree(), "physics_frame")

	assert_bool(chunk.is_chunk_loaded()).is_true()
	var ring_collision: Node = chunk.get_node_or_null("CriopodRingCollision")
	assert_object(ring_collision).is_not_null()
	var pod_index: int = int(ring_collision.slot_to_pod[level._selected_slot])
	assert_int(pod_index).is_greater(-1)
	var decorative_body: Node = ring_collision.get_node(ring_collision.body_path)
	var expected_shape_count := 0
	for mapped_pod in ring_collision.slot_to_pod:
		if int(mapped_pod) >= 0:
			expected_shape_count += 1
	assert_int(decorative_body.get_child_count()).is_equal(expected_shape_count - 1)
	assert_object(decorative_body.get_node_or_null("Pod_%02d" % pod_index)).is_null()
	var visual: Node = level.get_node("ScaffoldStreamRoot/Criopods_Visual")
	var visual_index: int = visual.instance_for_slot(level._selected_slot)
	assert_int(visual_index).is_greater(-1)
	assert_int(visual.hidden_instance_count()).is_equal(1)
	# El estado autoritativo del bloqueo es el indice oculto, no la transform del
	# MultiMesh: el backend `platform=server` (CI, headless) descarta los
	# transform_array por instancia y get_instance_transform() siempre devuelve
	# identidad. Verificado en GL (editor/X11): set_instance_transform() mueve las
	# tres capas a HIDDEN_ORIGIN. La verificacion visual queda para OYS/screenshot.
	assert_bool(visual._hidden.has(visual_index)).is_true()
	assert_object(level.get_node_or_null("Hub/Criopods/Item_%d" % level._selected_slot)).is_null()
	var shape: CollisionShape = decorative_body.get_child(0)
	assert_bool(shape.shape is BoxShape).is_true()
	var up: Vector3 = shape.global_transform.basis.y.normalized()
	var space = level.get_world().direct_space_state
	assert_bool(not space.intersect_ray(shape.global_transform.origin + up * 3.0, shape.global_transform.origin - up * 3.0, [], 64).empty()).is_true()


func test_pod_body_blocks_camera_with_environment_layer() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "physics_frame")

	var pilot: KinematicBody = level.get_node("Pilot")
	_disable_pilot_input(pilot)
	var spring_arm: Spatial = pilot.get_node("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm")
	var pod: Spatial = level.get_node("Criopod_Vert")
	var from: Vector3 = pod.to_global(Vector3(0.0, 1.5, -2.0))
	var to: Vector3 = pod.to_global(Vector3(0.0, 1.5, 0.0))
	var hit: Dictionary = pilot.get_world().direct_space_state.intersect_ray(
		from, to, [pilot], 1)

	assert_int(spring_arm.collision_mask & 1).is_equal(1)
	assert_bool(not hit.empty()).is_true()


func test_open_hatch_leaves_exit_corridor_clear() -> void:
	var level = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	yield(get_tree(), "physics_frame")

	var pilot: KinematicBody = level.get_node("Pilot")
	_disable_pilot_input(pilot)
	var pod: Spatial = level.get_node("Criopod_Vert")
	var hatch: Node = level.get_node("Criopod_Vert/RotatingObjectV2")
	hatch.set_active(true)
	yield(_wait_until_hatch_stops(hatch), "completed")

	var origin := pilot.global_transform.origin + pod.global_transform.basis.y.normalized() * 0.75
	var exit_direction := pod.global_transform.basis.z.normalized()
	var excluded: Array = [pilot]
	var pod_blocker: Node = null
	for _i in range(64):
		var hit: Dictionary = pilot.get_world().direct_space_state.intersect_ray(
			origin, origin + exit_direction * 1.5, excluded, 79)
		if hit.empty():
			break
		var collider: Node = hit.get("collider", null)
		if is_instance_valid(collider) and pod.is_a_parent_of(collider):
			pod_blocker = collider
			break
		excluded.append(collider)

	assert_object(pod_blocker).is_null()


# El shell/techo del criopod tiene que caer en el dither de props como el vidrio:
# el collider del DisplayCaseBody va en Entorno+Prop (65) para que PropDitherManager
# lo detecte y convierta la malla del shell, sin perder el bloqueo de camara (bit 1).
func test_criopod_shell_is_occlusion_prop() -> void:
	var pod = auto_free(CriopodScene.instance())
	add_child(pod)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var shell := pod as MeshInstance
	assert_int(shell.layers).is_equal(64)
	assert_int(pod.get_node("DisplayCaseBody").collision_layer & 64).is_equal(64)
	assert_int(pod.get_node("DisplayCaseBody").collision_layer & 1).is_equal(1)
	assert_bool(shell.get_active_material(0) is ShaderMaterial).is_true()

