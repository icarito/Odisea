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


func test_camera_does_not_snap_outward_when_collision_face_moves_farther() -> void:
	var root := _setup_root()
	var arm := _build_arm(root)
	var _wall := _spawn_wall(root, 3.0)

	yield(get_tree(), "idle_frame")
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
