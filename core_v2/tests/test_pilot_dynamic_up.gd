extends GdUnitTestSuite

# FD-323 Fase 1: invariancia rotacional del refactor `UP` -> `_up` en Pilot.
#
# SPIN_REAL sigue apagado, asi que en los modos actuales (STANDARD_1G, SPIN_WALKABLE,
# ZERO_G y SPIN_DYNAMIC) `_up == Vector3.UP`. Estos tests no cambian modos: verifican
# que la fisica de movimiento y salto es rotacionalmente equivalente para cualquier
# `up_dir` y que los helpers del controller normalizan con fallback seguro.

const PlayerMovementV2 = preload("res://core_v2/player/PlayerMovementV2.gd")
const PlayerJumpV2 = preload("res://core_v2/player/PlayerJumpV2.gd")
const PlayerControllerV2 = preload("res://core_v2/player/PlayerControllerV2.gd")

const DT := 1.0 / 60.0
const EPS := 0.002

func _up_variants() -> Array:
	return [
		Vector3.UP,
		Vector3.RIGHT,
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 1.0).normalized()
	]

# Rotacion minima que lleva Vector3.UP al up pedido. Permite comparar resultados en
# el frame canonico: back = rotation^-1 * resultado_mundial.
func _rotation_for_up(up_dir: Vector3) -> Basis:
	var target: Vector3 = up_dir.normalized()
	var dot_up: float = clamp(Vector3.UP.dot(target), -1.0, 1.0)
	if dot_up > 0.999999:
		return Basis.IDENTITY
	if dot_up < -0.999999:
		return Basis(Vector3.RIGHT, PI)
	var axis: Vector3 = Vector3.UP.cross(target).normalized()
	return Basis(axis, acos(dot_up))

func _make_movement() -> Node:
	var movement = auto_free(PlayerMovementV2.new())
	movement.is_tank_turn_mode = false
	return movement

func _make_jump() -> Node:
	return auto_free(PlayerJumpV2.new())

func _assert_back_equiv(expected: Vector3, world_result: Vector3, rotation: Basis, tolerance: float = EPS) -> void:
	var back: Vector3 = rotation.inverse().xform(world_result)
	assert_float(back.distance_to(expected)).is_less(tolerance)

func _simulate_jump_cut(up_dir: Vector3) -> Vector3:
	var jump = _make_jump()
	jump.buffer_jump()
	var velocity: Vector3 = jump.step_velocity(0.05, true, Vector3.ZERO, true, up_dir)
	velocity = jump.step_velocity(0.05, false, velocity, false, up_dir)
	velocity = jump.step_velocity(0.05, false, velocity, false, up_dir)
	return velocity

# --- Controller helpers ---------------------------------------------------------

func test_controller_sim_up_normalizes_and_falls_back() -> void:
	var controller = auto_free(PlayerControllerV2.new())
	assert_float(controller.get_sim_up().distance_to(Vector3.UP)).is_less(0.000001)

	controller.set_sim_up(Vector3(0.0, 7.0, 0.0))
	assert_float(controller.get_sim_up().distance_to(Vector3.UP)).is_less(0.000001)

	controller.set_sim_up(Vector3.RIGHT)
	assert_float(controller.get_sim_up().distance_to(Vector3.RIGHT)).is_less(0.000001)

	# Up invalido: conserva el anterior (no apaga la simulacion con un vector cero).
	controller.set_sim_up(Vector3.ZERO)
	assert_float(controller.get_sim_up().distance_to(Vector3.RIGHT)).is_less(0.000001)

	# Fallback defensivo si el estado interno quedara corrupto.
	controller._up = Vector3.ZERO
	assert_float(controller.get_sim_up().distance_to(Vector3.UP)).is_less(0.000001)

# --- PlayerMovementV2 -----------------------------------------------------------

func test_process_movement_is_rotation_equivariant() -> void:
	var move_vec := Vector2(0.35, -1.0)
	var canonical = _make_movement()
	canonical.process_movement(DT, move_vec, Basis.IDENTITY, false, true, false, Vector3.UP)
	var expected: Vector3 = canonical.horizontal_velocity
	assert_float(expected.length()).is_greater(0.0)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var movement = _make_movement()
		movement.set_floor_normal(up_dir, up_dir)
		movement.process_movement(DT, move_vec, rotation, false, true, false, up_dir)
		_assert_back_equiv(expected, movement.horizontal_velocity, rotation)

func test_process_movement_on_slope_uses_dynamic_up() -> void:
	var canonical_floor := Vector3(-0.35, 1.0, 0.0).normalized()
	var move_vec := Vector2(0.2, -1.0)
	var canonical_seed := Vector3(1.0, 0.0, 0.0)

	var canonical = _make_movement()
	canonical.set_floor_normal(canonical_floor, Vector3.UP)
	canonical.horizontal_velocity = canonical_seed
	canonical.process_movement(DT, move_vec, Basis.IDENTITY, false, true, false, Vector3.UP)
	var expected: Vector3 = canonical.horizontal_velocity

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var movement = _make_movement()
		movement.set_floor_normal(rotation.xform(canonical_floor), up_dir)
		movement.horizontal_velocity = rotation.xform(canonical_seed)
		movement.process_movement(DT, move_vec, rotation, false, true, false, up_dir)
		_assert_back_equiv(expected, movement.horizontal_velocity, rotation)

func test_align_to_floor_is_rotation_equivariant() -> void:
	var canonical_floor := Vector3(-0.35, 1.0, 0.0).normalized()
	var canonical_vector := Vector3(2.0, 0.0, 1.0)

	var base = _make_movement()
	base.set_floor_normal(canonical_floor, Vector3.UP)
	var expected: Vector3 = base.align_to_floor(canonical_vector, Vector3.UP)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var movement = _make_movement()
		movement.set_floor_normal(rotation.xform(canonical_floor), up_dir)
		var aligned: Vector3 = movement.align_to_floor(rotation.xform(canonical_vector), up_dir)
		_assert_back_equiv(expected, aligned, rotation)

func test_apply_slope_resistance_is_rotation_equivariant() -> void:
	var canonical_velocity := Vector3(3.0, 2.0, 1.0)
	var base = _make_movement()
	var expected: Vector3 = base.apply_slope_resistance(canonical_velocity, Vector3.UP)
	# El vector canonico debe superar el angulo minimo para que el test tenga mordida.
	assert_float(expected.distance_to(canonical_velocity)).is_greater(0.0)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var movement = _make_movement()
		var resisted: Vector3 = movement.apply_slope_resistance(rotation.xform(canonical_velocity), up_dir)
		_assert_back_equiv(expected, resisted, rotation)

# --- PlayerJumpV2 ---------------------------------------------------------------

func test_jump_gravity_is_rotation_equivariant() -> void:
	var base = _make_jump()
	var expected: Vector3 = base.step_velocity(DT, false, Vector3.ZERO, true, Vector3.UP)
	assert_float(expected.dot(Vector3.UP)).is_less(0.0)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var jump = _make_jump()
		var result: Vector3 = jump.step_velocity(DT, false, Vector3.ZERO, true, up_dir)
		_assert_back_equiv(expected, result, rotation, 0.0005)

func test_jump_impulse_is_rotation_equivariant() -> void:
	var base = _make_jump()
	base.buffer_jump()
	var expected: Vector3 = base.step_velocity(DT, true, Vector3.ZERO, true, Vector3.UP)
	assert_float(expected.dot(Vector3.UP)).is_equal_approx(12.0, 0.001)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var jump = _make_jump()
		jump.buffer_jump()
		var result: Vector3 = jump.step_velocity(DT, true, Vector3.ZERO, true, up_dir)
		_assert_back_equiv(expected, result, rotation, 0.0005)

func test_jump_variable_cut_is_rotation_equivariant() -> void:
	var expected: Vector3 = _simulate_jump_cut(Vector3.UP)
	# Tras soltar el salto, el recorte baja la componente up al minimo configurado.
	assert_float(expected.dot(Vector3.UP)).is_equal_approx(12.0 * 0.4, 0.001)

	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var result: Vector3 = _simulate_jump_cut(up_dir)
		_assert_back_equiv(expected, result, rotation, 0.0005)

func test_jump_step_velocity_preserves_planar_component() -> void:
	for up_dir in _up_variants():
		var rotation := _rotation_for_up(up_dir)
		var planar: Vector3 = rotation.xform(Vector3(1.0, 0.0, 0.5))
		planar = planar - up_dir * planar.dot(up_dir)
		var velocity: Vector3 = planar + up_dir * 2.0

		var jump = _make_jump()
		var result: Vector3 = jump.step_velocity(DT, false, velocity, false, up_dir)
		var result_planar: Vector3 = result - up_dir * result.dot(up_dir)
		assert_float(result_planar.distance_to(planar)).is_less(0.0005)
