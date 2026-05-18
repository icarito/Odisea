extends GdUnitTestSuite

const TestWorldRotatorScene = preload("res://core_v2/tests/TestWorldRotator.tscn")
const WorldRotatorScript = preload("res://core_v2/systems/WorldRotator.gd")
const GravityWorldScript = preload("res://core_v2/systems/GravityWorld.gd")

func test_test_scene_loads_world_rotator_script() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	var rotator = scene.get_node("WorldRotator")
	assert_object(rotator).is_not_null()
	assert_str(rotator.get_script().resource_path).is_equal("res://core_v2/systems/WorldRotator.gd")
	assert_bool(GravityWorld.has_rotator()).is_true()
	assert_object(GravityWorld.get_rotator()).is_same(rotator)
	assert_object(scene.get_node_or_null("PhysicalTerrace")).is_not_null()
	assert_object(scene.get_active_collision_body()).is_not_null()
	assert_object(scene.get_active_collision_body()).is_same(scene.get_node("PhysicalTerrace"))
	assert_float(rotator.spiral_blend).is_equal_approx(1.0, 0.001)
	assert_bool(rotator.auto_track_target_plate).is_true()

func test_test_scene_aligns_selected_plate_to_physical_terrace() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var selected: Transform = scene.get_selected_plate_global_transform()
	var target: Transform = scene.get_physical_terrace_transform()

	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.x.normalized().dot(target.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.z.normalized().dot(target.basis.z.normalized())).is_greater_equal(0.999)

	var player: Spatial = scene.get_node("Pilot")
	var player_on_plate: Vector3 = selected.affine_inverse().xform(player.global_transform.origin)
	assert_float(abs(player_on_plate.x)).is_less(5.0)
	assert_float(abs(player_on_plate.z)).is_less(5.0)

func test_test_scene_uses_explicit_physical_terrace_node() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	var physical_terrace: StaticBody = scene.get_node("PhysicalTerrace")
	assert_object(physical_terrace).is_not_null()
	var active_body: StaticBody = scene.get_active_collision_body()
	assert_object(active_body).is_not_null()
	assert_object(active_body).is_same(physical_terrace)
	assert_object(physical_terrace.get_node_or_null("CollisionShape")).is_not_null()
	assert_object(physical_terrace.get_node_or_null("MeshInstance")).is_null()

func test_test_scene_generates_neighbor_collision_proxies() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	assert_int(scene.get_generated_collision_count()).is_greater_equal(1)
	assert_object(scene.get_node_or_null("GeneratedTerraceCollisions")).is_not_null()

	var rotator = scene.get_node("WorldRotator")
	# Con pool_size=32 y 4 espirales de 48 plates, esperamos al menos 8 slots asignados.
	assert_int(scene.get_generated_collision_count()).is_greater_equal(8)

	# Buscar en el pool el slot asignado a la plate vecina (selected+1, misma espiral).
	var spiral_index: int = rotator.get_selected_spiral_index()
	var neighbor_plate: int = rotator.get_selected_plate_index() + 1
	var neighbor_body: StaticBody = null
	for body in rotator._collision_pool:
		if is_instance_valid(body) and int(body.get_meta("spiral_index")) == spiral_index and int(body.get_meta("plate_index")) == neighbor_plate:
			neighbor_body = body
			break
	assert_object(neighbor_body).is_not_null()

	var spiral: Spatial = rotator.get_platforms()[spiral_index]
	var visual_neighbor: Transform = rotator.global_transform * rotator.get_plate_canonical_transform(spiral, neighbor_plate)

	# El origin del pool debe coincidir con el visual completo.
	assert_float(neighbor_body.global_transform.origin.distance_to(visual_neighbor.origin)).is_less(0.02)
	# En TestWorldRotator (continuous_tracking = false) el pool sigue la orientación
	# visual exacta para que la colisión coincida con el mesh vecino.
	assert_float(neighbor_body.global_transform.basis.x.normalized().dot(visual_neighbor.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(neighbor_body.global_transform.basis.y.normalized().dot(visual_neighbor.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(neighbor_body.global_transform.basis.z.normalized().dot(visual_neighbor.basis.z.normalized())).is_greater_equal(0.999)

	# Raycast desde arriba del slot: debe golpear el StaticBody del pool.
	var from: Vector3 = neighbor_body.global_transform.origin + Vector3.UP * 6.0
	var to: Vector3 = neighbor_body.global_transform.origin - Vector3.UP * 6.0
	var hit: Dictionary = scene.get_world().direct_space_state.intersect_ray(from, to, [], 255)
	assert_bool(hit.has("collider")).is_true()
	assert_object(hit["collider"]).is_same(neighbor_body)

func test_test_scene_aligns_axial_up_to_ship_axis() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	var plate_canonical: Transform = rotator.get_selected_plate_canonical_transform()
	var actual_global_up: Vector3 = (rotator.global_transform * plate_canonical).basis.y.normalized()

	assert_float(actual_global_up.dot(Vector3.UP)).is_greater_equal(0.999)

func test_test_scene_does_not_roll_camera() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var camera: Camera = scene.get_node("Pilot/CameraRig/Yaw/Pitch/SpringArm/Camera")
	camera.rotation.z = deg2rad(20.0)
	scene._process(0.016)

	assert_float(camera.rotation.z).is_equal_approx(0.0, 0.001)

func test_test_scene_tracks_player_to_neighbor_plate_and_rebuilds_collisions() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	rotator.rotation_speed = 1000.0
	# Desactivar continuous_tracking para probar plate-tracking deterministamente.
	rotator.continuous_tracking = false
	var player: Spatial = scene.get_node("Pilot")
	var spiral_index: int = rotator.get_selected_spiral_index()
	var next_plate: int = rotator.get_selected_plate_index() + 1
	var third_neighbor: int = next_plate + 3
	var spiral: Spatial = rotator.get_platforms()[spiral_index]
	var target_global: Transform = rotator.global_transform * rotator.get_plate_canonical_transform(spiral, next_plate)
	player.global_transform.origin = target_global.origin + Vector3.UP * 8.0
	if player.has_method("set_external_velocity"):
		player.set_external_velocity(Vector3.ZERO)

	for _i in range(120):
		yield(get_tree(), "physics_frame")
		if rotator.get_selected_plate_index() == next_plate:
			break
	rotator._slerp_to_global_transform(1.0)
	# Forzar reasignación del pool al nuevo centro.
	rotator._assign_pool_to_nearest_plates()

	assert_int(rotator.get_selected_plate_index()).is_equal(next_plate)
	assert_int(scene.get_generated_collision_count()).is_greater_equal(rotator.collision_pool_size - 4)

	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = rotator.get_active_collision_transform()
	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)



func test_gravity_world_vertical_mode_is_normal_down_and_one_g() -> void:
	var manager = auto_free(GravityWorldScript.new())
	manager.one_g_strength = 9.81
	manager.set_gravity_blend(0.0)

	var gravity: Vector3 = manager.get_canonical_gravity(Vector3(100.0, 20.0, 0.0))
	assert_float(gravity.normalized().dot(Vector3.DOWN)).is_greater_equal(0.999)
	assert_float(gravity.length()).is_equal_approx(9.81, 0.001)

func test_gravity_world_centrifugal_mode_is_radial_and_scales_with_radius() -> void:
	var manager = auto_free(GravityWorldScript.new())
	manager.one_g_strength = 9.81
	manager.set_gravity_blend(1.0)
	manager.set_ship_axis(Vector3.ZERO, Vector3.UP)
	manager.set_centrifugal_reference_radius(10.0)
	manager.set_ship_angular_velocity(0.0)

	var near_gravity: Vector3 = manager.get_canonical_gravity(Vector3(10.0, 5.0, 0.0))
	var far_gravity: Vector3 = manager.get_canonical_gravity(Vector3(20.0, 5.0, 0.0))

	assert_float(near_gravity.normalized().dot(Vector3.RIGHT)).is_greater_equal(0.999)
	assert_float(near_gravity.length()).is_equal_approx(9.81, 0.001)
	assert_float(far_gravity.length()).is_equal_approx(19.62, 0.001)

func test_rotator_aligns_child_platform_up_to_global_up() -> void:
	var root: Spatial = auto_free(Spatial.new())
	add_child(root)

	var rotator = WorldRotatorScript.new()
	rotator.name = "WorldRotator"
	rotator.rotation_speed = 1000.0
	root.add_child(rotator)

	var platform: Spatial = Spatial.new()
	platform.name = "WallPlatform"
	platform.transform.basis = Basis(Vector3.RIGHT, deg2rad(90.0))
	rotator.add_child(platform)

	yield(get_tree(), "idle_frame")
	rotator.register_platform(platform)
	rotator.navigate_to(platform)
	rotator._slerp_to_target(1.0)

	var platform_up: Vector3 = platform.global_transform.basis.y.normalized()
	assert_float(platform_up.dot(Vector3.UP)).is_greater_equal(0.999)
