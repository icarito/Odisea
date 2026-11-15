extends GdUnitTestSuite

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")
const MagRailScript = preload("res://core_v2/props/magrail/MagRail.gd")
const InputDataScript = preload("res://core_v2/input/InputDataV2.gd")

const FIXED_DT := 1.0 / 60.0


func _setup_root(tag: String) -> Spatial:
	var root := Spatial.new()
	root.name = "MagRailTestRoot_" + tag
	root.translation = Vector3(4000.0, 4000.0, 4000.0)
	get_tree().root.add_child(root)
	return root


func _add_floor(root: Spatial) -> void:
	var body := StaticBody.new()
	var shape := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(40.0, 0.5, 60.0)
	shape.shape = box
	body.add_child(shape)
	body.translation = Vector3(0.0, -0.5, -20.0)
	root.add_child(body)


func _setup_player(root: Node, at: Vector3) -> KinematicBody:
	var player := KinematicBody.new()
	player.name = "Pilot"
	var collision := CollisionShape.new()
	collision.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	collision.shape = capsule
	collision.transform = Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 1.5, 0))
	player.add_child(collision)
	var camera_rig := Spatial.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)
	var visual := Spatial.new()
	visual.name = "Visual"
	player.add_child(visual)
	var pivot := Spatial.new()
	pivot.name = "Pivot"
	visual.add_child(pivot)
	player.set_script(PlayerControllerScript)
	player.translation = at
	player.collision_layer = 2
	# Desactivar _physics_process automatico para controlar step() determinista en tests unitarios.
	player.is_replay_mode = true
	player.external_input_provided = false
	root.add_child(player)
	return player


func _make_straight_rail(parent: Node, p0: Vector3, p1: Vector3) -> Path:
	var rail := Path.new()
	rail.name = "MagRail"
	rail.set_script(MagRailScript)
	var curve := Curve3D.new()
	curve.add_point(p0)
	curve.add_point(p1)
	rail.curve = curve
	parent.add_child(rail)
	return rail


func _make_curved_rail(parent: Node) -> Path:
	var rail := Path.new()
	rail.name = "MagRailCurve"
	rail.set_script(MagRailScript)
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0.4, 0), Vector3.ZERO, Vector3(0, 0, -5))
	curve.add_point(Vector3(4, 0.4, -12), Vector3(-4, 0, 4), Vector3(4, 0, -4))
	curve.add_point(Vector3(12, 0.4, -20), Vector3(-4, 0, 0), Vector3.ZERO)
	rail.curve = curve
	parent.add_child(rail)
	return rail


func _make_input(move_y: float = -1.0, move_x: float = 0.0, jump: bool = false, sprint: bool = true) -> InputDataV2:
	var inp := InputDataScript.new()
	inp.move_vec = Vector2(move_x, move_y)
	inp.jump = jump
	inp.sprint = sprint
	return inp


func test_magrail_engage_and_sustained_speed() -> void:
	var root := _setup_root("Straight")
	_add_floor(root)
	var rail := _make_straight_rail(root, Vector3(0, 0.4, 0), Vector3(0, 0.4, -22))
	var player := _setup_player(root, Vector3(0, 0.0, 2.0))

	var engaged := false
	var peak_speed := 0.0
	for _i in range(180):
		player.step(FIXED_DT, _make_input(-1.0, 0.0, false, true))
		if player.movement_logic.is_on_rail:
			engaged = true
			var h_spd := Vector2(player.velocity.x, player.velocity.z).length()
			if h_spd > peak_speed:
				peak_speed = h_spd

	assert_bool(engaged).is_true()
	assert_float(peak_speed).is_greater_equal(rail.min_rail_speed - 0.1)
	assert_float(player.translation.z).is_less(-18.0)
	root.queue_free()


func test_magrail_jump_exit_preserves_momentum() -> void:
	var root := _setup_root("JumpExit")
	_add_floor(root)
	var rail := _make_straight_rail(root, Vector3(0, 0.6, 0), Vector3(0, 0.6, -30))
	var player := _setup_player(root, Vector3(0, 0.6, -1.0))

	# Enganchar y acelerar en el riel.
	for _i in range(25):
		player.step(FIXED_DT, _make_input(-1.0, 0.0, false, true))
	assert_bool(player.movement_logic.is_on_rail).is_true()

	# Saltar del riel.
	player.step(FIXED_DT, _make_input(-1.0, 0.0, true, true))
	assert_bool(player.movement_logic.is_on_rail).is_false()
	assert_float(player.velocity.y).is_greater(5.0)
	var launch_horiz := Vector2(player.velocity.x, player.velocity.z).length()
	assert_float(launch_horiz).is_greater_equal(rail.min_rail_speed * 0.9)

	# Verificar que conserva el momentum en el aire sin input.
	for _j in range(10):
		player.step(FIXED_DT, _make_input(0.0, 0.0, false, false))
	var air_horiz := Vector2(player.velocity.x, player.velocity.z).length()
	assert_float(air_horiz).is_greater_equal(rail.min_rail_speed * 0.85)
	root.queue_free()


func test_magrail_curve_drift_and_inertia() -> void:
	var root := _setup_root("Curve")
	_add_floor(root)
	var _rail := _make_curved_rail(root)
	var player := _setup_player(root, Vector3(0, 0.4, -0.5))

	var max_drift := 0.0
	for _i in range(110):
		player.step(FIXED_DT, _make_input(-1.0, 0.0, false, true))
		if player.movement_logic.is_on_rail:
			var d := abs(player.movement_logic._rail_drift_offset)
			if d > max_drift:
				max_drift = d

	assert_float(max_drift).is_greater(0.005)
	assert_float(player.translation.x).is_greater(5.0)
	assert_float(player.translation.z).is_less(-12.0)
	root.queue_free()


func test_magrail_moving_platform_compatibility() -> void:
	var root := _setup_root("MovingPlat")
	_add_floor(root)
	var plat := Spatial.new()
	plat.name = "MovingPlatform"
	root.add_child(plat)
	var rail := _make_straight_rail(plat, Vector3(0, 0.5, 0), Vector3(0, 0.5, -10))
	var player := _setup_player(root, Vector3(0, 0.5, -0.5))

	var platform_vx := 4.0
	var exit_vx := 0.0
	var exited := false
	for _i in range(90):
		plat.translation.x += platform_vx * FIXED_DT
		rail._physics_process(FIXED_DT)
		player.step(FIXED_DT, _make_input(-1.0, 0.0, false, true))
		if not player.movement_logic.is_on_rail and _i > 10 and not exited:
			exited = true
			exit_vx = player.velocity.x
			break

	assert_bool(exited).is_true()
	assert_float(exit_vx).is_greater(2.5)
	root.queue_free()


func test_magrail_snapshot_determinism() -> void:
	var root := _setup_root("Determinism")
	_add_floor(root)
	var _rail := _make_curved_rail(root)
	var player := _setup_player(root, Vector3(0, 0.4, -0.5))

	# Avanzar hasta entrar en la curva del riel.
	for _i in range(25):
		player.step(FIXED_DT, _make_input(-1.0, 0.2, false, true))
	assert_bool(player.movement_logic.is_on_rail).is_true()

	var snap: Dictionary = player.get_full_snapshot()
	var inputs := []
	for k in range(35):
		var jump := (k == 20)
		inputs.append(_make_input(-1.0, -0.3 if k < 15 else 0.4, jump, true))

	for inp in inputs:
		player.step(FIXED_DT, inp)
	var pos_a: Vector3 = player.global_transform.origin
	var vel_a: Vector3 = player.velocity

	player.restore_snapshot(snap)
	for inp in inputs:
		player.step(FIXED_DT, inp)
	var pos_b: Vector3 = player.global_transform.origin
	var vel_b: Vector3 = player.velocity

	assert_float(pos_a.distance_to(pos_b)).is_less(0.0001)
	assert_float(vel_a.distance_to(vel_b)).is_less(0.0001)
	root.queue_free()
