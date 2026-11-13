extends GdUnitTestSuite

# CircuitCable — interacción física con la catenaria (oscilador amortiguado determinista).

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


func _fake_body(velocity: Vector3) -> Node:
	var b = FakeBody.new()
	b.velocity = velocity
	add_child(b)
	b.global_transform.origin = Vector3.ZERO
	return b


func test_cable_participates_in_replay_sync_and_snapshots_sway() -> void:
	var cable = _make_cable()
	assert_bool(cable.is_in_group("replay_sync")).is_true()
	var snap: Dictionary = cable.get_snapshot()
	assert_bool(snap.has("sway")).is_true()
	assert_bool(snap.has("sway_vel")).is_true()
	assert_bool(snap.has("spark")).is_true()


func test_body_pass_deflects_the_catenary() -> void:
	var cable = _make_cable()
	assert_float(cable._sway_offset.length()).is_equal_approx(0.0, 0.000001)
	cable._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	assert_float(cable._sway_offset.length()).is_equal_approx(0.0, 0.000001)  # aún no integró
	_step(cable, 1)
	assert_float(cable._sway_offset.length()).is_greater(0.0001)
	# La deformación es perpendicular al eje del cable (eje X) y tiene componente Z.
	assert_float(abs(cable._sway_offset.x)).is_less(0.0001)
	assert_float(abs(cable._sway_offset.z)).is_greater(0.0001)


func test_sway_decays_back_to_rest() -> void:
	var cable = _make_cable()
	var body = _fake_body(Vector3(0, 0, 6))
	cable._on_hurtbox_body_entered(body)
	_step(cable, 6)
	var early: float = cable._sway_offset.length()
	assert_float(early).is_greater(0.0001)
	# El cuerpo sale del área: el empuje sostenido cesa y el oscilador se amortigua.
	cable._on_hurtbox_body_exited(body)
	_step(cable, 300)
	assert_float(cable._sway_offset.length()).is_less(0.002)
	assert_float(cable._sway_velocity.length()).is_less(0.01)


func test_sway_is_deterministic_for_identical_inputs() -> void:
	var a = _make_cable()
	var b = _make_cable()
	a._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	b._on_hurtbox_body_entered(_fake_body(Vector3(0, 0, 6)))
	var max_diff := 0.0
	for _i in range(120):
		a._physics_process(1.0 / 60.0)
		b._physics_process(1.0 / 60.0)
		max_diff = max(max_diff, (a._sway_offset - b._sway_offset).length())
	assert_float(max_diff).is_less(0.000001)
	# Y el snapshot reproduce el estado exacto (replay).
	var saved: Dictionary = a.get_snapshot()
	var offset_before: Vector3 = a._sway_offset
	a._sway_offset = Vector3.ZERO
	a._sway_velocity = Vector3.ZERO
	a.restore_snapshot(saved)
	assert_float((a._sway_offset - offset_before).length()).is_less(0.000001)


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
