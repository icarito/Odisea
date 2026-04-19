extends GdUnitTestSuite

const KinematicArm3DScript = preload("res://core_v2/camera/KinematicArm3D.gd")


func _setup_root() -> Spatial:
	var root := Spatial.new()
	root.name = "KinematicArm3DTestRoot"
	get_tree().root.add_child(root)
	return root


func _teardown_root(root: Node) -> void:
	if root and is_instance_valid(root):
		root.queue_free()
	yield(get_tree(), "idle_frame")


func _build_arm(root: Spatial) -> KinematicArm3D:
	var arm := KinematicArm3DScript.new()
	arm.name = "SpringArm"
	arm.current_length = 1.0
	arm.spring_length = 6.0
	arm.target_length = 6.0
	arm.min_length = 0.5
	arm.weight = 600.0
	arm.extend_weight = 2.0
	arm.retract_weight = 18.0
	arm.collision_shrink_weight = 18.0
	arm.collision_padding = 0.0

	var sphere := SphereShape.new()
	sphere.radius = 0.2
	arm.collider_shape = sphere

	var camera := Camera.new()
	camera.name = "Camera"
	arm.add_child(camera)

	root.add_child(arm)
	return arm


func _spawn_wall(root: Spatial, z_center: float) -> StaticBody:
	var wall := StaticBody.new()
	wall.name = "Wall"

	var shape := CollisionShape.new()
	shape.name = "CollisionShape"
	var box := BoxShape.new()
	box.extents = Vector3(2.0, 2.0, 0.1)
	shape.shape = box
	shape.transform.origin = Vector3(0.0, 0.0, z_center)
	wall.add_child(shape)

	root.add_child(wall)
	return wall


func _spawn_ceiling(root: Spatial, y_center: float) -> StaticBody:
	var ceiling := StaticBody.new()
	ceiling.name = "Ceiling"

	var shape := CollisionShape.new()
	shape.name = "CollisionShape"
	var box := BoxShape.new()
	box.extents = Vector3(4.0, 0.1, 8.0)
	shape.shape = box
	shape.transform.origin = Vector3(0.0, y_center, 4.0)
	ceiling.add_child(shape)

	root.add_child(ceiling)
	return ceiling


func test_camera_does_not_snap_outward_when_collision_face_moves_farther() -> void:
	var root := _setup_root()
	var arm := _build_arm(root)
	var _wall := _spawn_wall(root, 3.0)

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")

	var camera: Camera = arm.get_node("Camera")
	var rendered_distance := arm.global_transform.origin.distance_to(camera.global_transform.origin)

	assert_float(arm.current_length).is_less(2.0)
	assert_float(rendered_distance).is_less(2.0)
	assert_float(abs(rendered_distance - arm.current_length)).is_less(0.15)

	yield(_teardown_root(root), "completed")


func test_collision_latch_holds_small_hit_fluctuations() -> void:
	var arm := KinematicArm3DScript.new()
	arm.extend_weight = 6.0
	arm.collision_hold_epsilon = 0.08
	arm.collision_release_hysteresis = 0.18
	arm.collision_release_delay = 0.1

	var initial := arm._resolve_collision_hit_length(6.05, 1.0 / 60.0)
	var tiny_variation := arm._resolve_collision_hit_length(6.10, 1.0 / 60.0)
	var medium_variation := arm._resolve_collision_hit_length(6.20, 1.0 / 60.0)

	assert_float(initial).is_equal(6.05)
	assert_float(tiny_variation).is_equal(6.05)
	assert_float(medium_variation).is_equal(6.05)

	arm.free()


func test_idle_collision_latch_survives_flickering_misses() -> void:
	var arm := KinematicArm3DScript.new()
	arm.current_length = 4.6
	arm.target_length = 5.0
	arm.spring_length = 5.0
	arm.collision_miss_grace = 0.1
	arm.collision_jitter_epsilon = 0.035
	arm._resolve_collision_hit_length(4.6, 1.0 / 60.0)

	for _i in range(90):
		var advanced := arm._advance_clear_length(1.0 / 60.0)
		assert_float(advanced).is_equal(4.6)

	assert_float(arm._collision_latched_length).is_equal(4.6)

	arm.transform.origin += Vector3(0.1, 0.0, 0.0)
	var released := arm._advance_clear_length(1.0 / 60.0)

	assert_float(released).is_greater(4.6)
	assert_float(arm._collision_latched_length).is_equal(-1.0)

	arm.free()


func test_farther_collision_hit_must_persist_before_latch_releases() -> void:
	var arm := KinematicArm3DScript.new()
	arm.collision_hold_epsilon = 0.08
	arm.collision_release_hysteresis = 0.18
	arm.collision_release_delay = 0.1

	var initial := arm._resolve_collision_hit_length(4.6, 1.0 / 60.0)
	var early_farther := arm._resolve_collision_hit_length(4.9, 1.0 / 60.0)
	var persisted_farther := arm._resolve_collision_hit_length(4.9, 0.1)

	assert_float(initial).is_equal(4.6)
	assert_float(early_farther).is_equal(4.6)
	assert_float(persisted_farther).is_equal(4.9)

	arm.free()


func test_ceiling_accommodation_preserves_zoom_when_adjusted_target_is_clear() -> void:
	var root := _setup_root()
	var arm := _build_arm(root)
	arm.current_length = 6.0
	arm.spring_length = 6.0
	arm.target_length = 6.0
	arm.transform.basis = Basis(Vector3.RIGHT, deg2rad(-30.0))
	arm.ceiling_margin = 0.25
	arm.ceiling_check_distance = 3.0
	var _ceiling := _spawn_ceiling(root, 1.8)

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")

	var camera: Camera = arm.get_node("Camera")

	assert_float(arm.current_length).is_greater(5.5)
	assert_bool(arm.is_zoom_out_blocked()).is_true()
	assert_float(camera.global_transform.origin.y).is_less(1.56)
	assert_float(arm.global_transform.origin.distance_to(camera.global_transform.origin)).is_greater(5.2)

	yield(_teardown_root(root), "completed")
