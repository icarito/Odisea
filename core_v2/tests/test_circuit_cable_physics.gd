extends GdUnitTestSuite

# CircuitCable — catenaria como cuerda física (Verlet/PBD determinista).

const CableScript = preload("res://core_v2/systems/circuit/CircuitCable.gd")

class FakeBody:
	extends KinematicBody
	var velocity := Vector3.ZERO


func _make_cable() -> Node:
	var cable = CableScript.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(-2, 0, 0))
	curve.add_point(Vector3(2, 0, 0))
	cable.path_curve = curve
	cable.cable_radius = 0.05
	cable.cable_sides = 6
	auto_free(cable)
	add_child(cable)
	return cable


func _step(cable, frames: int, dt: float = 1.0 / 60.0) -> void:
	for _i in range(frames):
		cable._physics_process(dt)


func _fake_body(velocity: Vector3, position: Vector3 = Vector3.ZERO) -> Node:
	var b = FakeBody.new()
	b.velocity = velocity
	add_child(b)
	b.global_transform.origin = position
	return b


func _mid_index(cable) -> int:
	return int(cable._points.size() / 2)


func _max_deviation(cable) -> float:
	var worst := 0.0
	for i in range(cable._points.size()):
		worst = max(worst, cable._points[i].distance_to(cable._base_points[i]))
	return worst


func _max_speed(cable) -> float:
	var worst := 0.0
	for i in range(1, cable._points.size() - 1):
		worst = max(worst, (cable._points[i] - cable._prev_points[i]).length())
	return worst


func test_cable_participates_in_replay_sync_and_snapshots_rope() -> void:
	var cable = _make_cable()
	assert_bool(cable.is_in_group("replay_sync")).is_true()
	var snap: Dictionary = cable.get_snapshot()
	assert_bool(snap.has("rope")).is_true()
	assert_bool(snap.has("rope_prev")).is_true()
	assert_bool(snap.has("rope_kick")).is_true()
	assert_bool(snap.has("spark")).is_true()


func test_body_pass_deflects_the_catenary() -> void:
	var cable = _make_cable()
	var mid := _mid_index(cable)
	assert_float(cable._points[mid].distance_to(cable._base_points[mid])).is_equal_approx(0.0, 0.000001)
	cable._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	assert_float(cable._points[mid].distance_to(cable._base_points[mid])).is_equal_approx(0.0, 0.000001)  # aún no integró
	_step(cable, 1)
	var dev: Vector3 = cable._points[mid] - cable._base_points[mid]
	assert_float(dev.length()).is_greater(0.0001)
	# Deflexión lateral perpendicular al eje del cable (eje X).
	assert_float(abs(dev.x)).is_less(0.001)
	assert_float(abs(dev.z)).is_greater(0.0001)
	# Extremos anclados: no se mueven.
	assert_float(cable._points[0].distance_to(cable._base_points[0])).is_less(0.000001)
	assert_float(cable._points[cable._points.size() - 1].distance_to(cable._base_points[cable._points.size() - 1])).is_less(0.000001)


func test_rope_sags_under_gravity() -> void:
	var cable = _make_cable()
	# Sin cuerpos: la gravedad debe colgar el centro por debajo de la base recta.
	_step(cable, 2400)
	var mid := _mid_index(cable)
	assert_float(cable._points[mid].y).is_less(cable._base_points[mid].y - 0.004)


func test_rope_deformation_is_localized_near_contact() -> void:
	var cable = _make_cable()
	var n: int = cable._points.size()
	var near_idx: int = int(float(n) * 0.25)
	var far_idx: int = int(float(n) * 0.85)
	var body = _fake_body(Vector3(0, 0, 6), Vector3(-1, 0, 0))
	cable._on_hurtbox_body_entered(body)
	_step(cable, 2)
	var near_dev: float = cable._points[near_idx].distance_to(cable._base_points[near_idx])
	var far_dev: float = cable._points[far_idx].distance_to(cable._base_points[far_idx])
	assert_float(near_dev).is_greater(0.001)
	assert_bool(far_dev < near_dev * 0.5).is_true()
	# Extremos anclados.
	assert_float(cable._points[0].distance_to(cable._base_points[0])).is_less(0.000001)
	assert_float(cable._points[n - 1].distance_to(cable._base_points[n - 1])).is_less(0.000001)


func test_sway_decays_back_to_rest() -> void:
	var cable = _make_cable()
	var body = _fake_body(Vector3(0, 0, 6))
	cable._on_hurtbox_body_entered(body)
	_step(cable, 6)
	assert_float(_max_deviation(cable)).is_greater(0.0001)
	cable._on_hurtbox_body_exited(body)
	_step(cable, 900)
	var settle: Array = []
	for p in cable._points:
		settle.append(Vector3(p.x, p.y, p.z))
	_step(cable, 120)
	var drift := 0.0
	for i in range(cable._points.size()):
		drift = max(drift, cable._points[i].distance_to(settle[i]))
	assert_float(drift).is_less(0.003)
	assert_float(_max_speed(cable)).is_less(0.0015)


func test_sway_is_deterministic_for_identical_inputs() -> void:
	var a = _make_cable()
	var b = _make_cable()
	a._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	b._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	var max_diff := 0.0
	for _i in range(120):
		a._physics_process(1.0 / 60.0)
		b._physics_process(1.0 / 60.0)
		for i in range(a._points.size()):
			max_diff = max(max_diff, (a._points[i] - b._points[i]).length())
	assert_float(max_diff).is_less(0.000001)
	# Y el snapshot reproduce el estado exacto (replay).
	var saved: Dictionary = a.get_snapshot()
	var before: Array = []
	for p in a._points:
		before.append(Vector3(p.x, p.y, p.z))
	a._points = PoolVector3Array()
	a._prev_points = PoolVector3Array()
	a._kick_v = PoolVector3Array()
	a.restore_snapshot(saved)
	var diff2 := 0.0
	for i in range(a._points.size()):
		diff2 = max(diff2, a._points[i].distance_to(before[i]))
	assert_float(diff2).is_less(0.000001)


func test_collision_shape_is_not_rebuilt_during_sway() -> void:
	var cable = _make_cable()
	var col_body = cable.get_node_or_null("CableVis/CableVis_col")
	assert_object(col_body).is_not_null()
	var shape_before = _first_collision_shape(col_body)
	assert_object(shape_before).is_not_null()
	cable._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	_step(cable, 30)
	var shape_after = _first_collision_shape(col_body)
	assert_bool(shape_after == shape_before).is_true()


func _first_collision_shape(body) -> Shape:
	for c in body.get_children():
		if c is CollisionShape:
			return c.shape
	return null


func test_energized_cable_emits_spark_on_impulse() -> void:
	var cable = _make_cable()
	cable.set_active(true, true)
	assert_float(cable._spark).is_equal_approx(0.0, 0.000001)
	cable._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	assert_float(cable._spark).is_greater(0.0)
	# La chispa decae y no se queda pegada.
	_step(cable, 60)
	assert_float(cable._spark).is_equal_approx(0.0, 0.000001)


func test_damage_still_works() -> void:
	var cable = _make_cable()
	assert_bool(cable.is_broken()).is_false()
	cable.take_damage(999.0)
	assert_bool(cable.is_broken()).is_true()
