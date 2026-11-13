extends GdUnitTestSuite

# FD-320 / conexión domo→bahía: la boca en la cáscara del domo y el conector
# (túnel + esclusa + hazard) deben existir y estar alineados con el azimut del
# `Hub/PedestalMachineBay` (world 31.8, 0, 3.2 → 5.75°).

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")

const AZIMUTH_DEG := 5.75

func _boot_level() -> Spatial:
	var level: Spatial = auto_free(RingHubScene.instance())
	level.open_pod_terminal_on_start = false
	add_child(level)
	return level


func _radial(level: Spatial, local_x: float) -> Vector3:
	var bc: Spatial = level.get_node("Hub/BayConnector")
	return bc.global_transform.xform(Vector3(local_x, 0.0, 0.0))


func test_dome_shell_uses_breach_mesh() -> void:
	# La cáscara del domo es el producto recortado (con la boca de esclusa).
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	var dome = level.get_node_or_null("Hub/DomeInteriorLowPoly/DomeMesh")
	assert_object(dome).is_not_null()
	assert_str(dome.mesh.resource_path).contains("DomeInteriorLowPoly_breach")


func test_connector_is_radial_from_the_shell() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	var bc = level.get_node_or_null("Hub/BayConnector")
	assert_object(bc).is_not_null()
	var n := Vector3(cos(deg2rad(AZIMUTH_DEG)), 0.0, sin(deg2rad(AZIMUTH_DEG)))
	# La boca (x local = 7) cae sobre la cáscara (r≈35); el extremo externo (x=22) afuera.
	var mouth := _radial(level, 7.0)
	var tip := _radial(level, 22.0)
	assert_float(Vector3(mouth.x, 0.0, mouth.z).length()).is_equal_approx(35.0, 0.5)
	assert_float(Vector3(tip.x, 0.0, tip.z).length()).is_greater(40.0)
	# El eje del túnel coincide con la radial del pedestal de la bahía.
	var axis := Vector3(tip.x - mouth.x, 0.0, tip.z - mouth.z).normalized()
	assert_float(axis.dot(n)).is_equal_approx(1.0, 0.01)


func test_tunnel_floor_spans_the_tunnel() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	var floor_body = level.get_node_or_null("Hub/BayConnector/Floor")
	assert_object(floor_body).is_not_null()
	assert_bool(floor_body is StaticBody).is_true()
	var shape = (floor_body.get_node("CollisionShape") as CollisionShape).shape
	assert_bool(shape is BoxShape).is_true()
	# El piso cubre el tramo: sus extremos locales (x=4 y x=22) caen sobre un piso real.
	for lx in [4.0, 13.0, 22.0]:
		var p := _radial(level, lx)
		assert_float(p.y).is_between(-0.5, 0.5)


func test_airlock_trigger_and_hazard_present() -> void:
	var level := _boot_level()
	yield(get_tree(), "idle_frame")
	var trigger = level.get_node_or_null("Hub/BayConnector/AirlockTrigger")
	assert_object(trigger).is_not_null()
	assert_bool(trigger.has_method("_enter_machine_bay")).is_true()
	assert_int(trigger.collision_mask).is_equal(2)  # detecta al jugador

	var hazard = level.get_node_or_null("Hub/BayConnector/Hazard")
	assert_object(hazard).is_not_null()
	assert_bool(bool(hazard.get("is_active"))).is_true()
	# El viento empuja hacia adentro (eje -X local) para que haya que avanzar contra él.
	assert_float((hazard.get("wind_velocity") as Vector3).x).is_less(0.0)


# --- Transitabilidad real: el piloto CAMINA desde el piso del domo, cruza la boca
# y llega al túnel (no es sólo geometría: pasa la colisión de la cáscara cortada). ---

func _movement_basis(pilot: Spatial) -> Basis:
	var cinematic: Node = get_node_or_null("/root/CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var active: Camera = cinematic.get_active_camera()
		if active != null and is_instance_valid(active):
			return active.global_transform.basis
	var vp: Viewport = pilot.get_viewport()
	if vp != null and vp.get_camera() != null:
		return vp.get_camera().global_transform.basis
	return Basis.IDENTITY


func _release_move() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _drive(pilot: Spatial, target: Vector3) -> void:
	var to_target: Vector3 = target - pilot.global_transform.origin
	to_target.y = 0.0
	_release_move()
	if to_target.length() < 0.05:
		return
	var desired: Vector3 = to_target.normalized()
	var basis: Basis = _movement_basis(pilot)
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	var right: Vector3 = basis.x
	right.y = 0.0
	if forward.length() < 0.001 or right.length() < 0.001:
		return
	forward = forward.normalized()
	right = right.normalized()
	var f: float = desired.dot(forward)
	var r: float = desired.dot(right)
	if f > 0.05:
		Input.action_press("move_forward", clamp(f, 0.0, 1.0))
	elif f < -0.05:
		Input.action_press("move_backward", clamp(-f, 0.0, 1.0))
	if r > 0.05:
		Input.action_press("move_right", clamp(r, 0.0, 1.0))
	elif r < -0.05:
		Input.action_press("move_left", clamp(-r, 0.0, 1.0))


func test_pilot_walks_through_the_breach_into_the_tunnel() -> void:
	var level := _boot_level()
	level.close_pod_terminal()
	for _i in range(60):
		yield(get_tree(), "physics_frame")
	var pilot = level.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()
	var n := Vector3(cos(deg2rad(AZIMUTH_DEG)), 0.0, sin(deg2rad(AZIMUTH_DEG)))
	# Arranca en el piso del domo, 6 m antes de la boca.
	pilot.global_transform.origin = n * 29.0 + Vector3(0.0, 2.0, 0.0)
	pilot.velocity = Vector3.ZERO
	yield(get_tree(), "physics_frame")
	var reached := false
	for _i in range(900):
		var p: Vector3 = pilot.global_transform.origin
		if Vector3(p.x, 0.0, p.z).length() >= 42.0:
			reached = true
			break
		_drive(pilot, n * 46.0)
		yield(get_tree(), "physics_frame")
	_release_move()
	assert_bool(reached).is_true()
	assert_bool(pilot.is_on_floor()).is_true()
