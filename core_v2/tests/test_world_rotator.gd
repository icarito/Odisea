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
	assert_object(rotator.get_active_collision_body()).is_not_null()
	assert_object(rotator.get_active_collision_body()).is_same(scene.get_node("PhysicalTerrace"))
	assert_float(rotator.spiral_blend).is_equal_approx(1.0, 0.001)
	assert_bool(rotator.auto_track_target_plate).is_true()
	assert_bool(rotator.apply_selection_on_ready).is_true()

func test_test_scene_aligns_selected_plate_to_physical_terrace() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = scene.get_node("PhysicalTerrace").global_transform

	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.x.normalized().dot(target.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.z.normalized().dot(target.basis.z.normalized())).is_greater_equal(0.999)
	assert_float(target.basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)

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
	var rotator = scene.get_node("WorldRotator")
	var active_body: StaticBody = rotator.get_active_collision_body()
	assert_object(active_body).is_not_null()
	assert_object(active_body).is_same(physical_terrace)
	assert_object(physical_terrace.get_node_or_null("CollisionShape")).is_not_null()
	assert_object(physical_terrace.get_node_or_null("MeshInstance")).is_null()

func test_test_scene_generates_neighbor_collision_proxies() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	assert_int(rotator.get_generated_collision_count()).is_greater_equal(1)
	assert_object(scene.get_node_or_null("GeneratedTerraceCollisions")).is_not_null()

	# Con pool_size=32 y 4 espirales de 48 plates, esperamos al menos 8 slots asignados.
	assert_int(rotator.get_generated_collision_count()).is_greater_equal(8)

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
	var neighbor_shape: CollisionShape = neighbor_body.get_node("CollisionShape")
	var neighbor_box: BoxShape = neighbor_shape.shape as BoxShape
	var visual_extents: Vector3 = rotator._get_plate_collision_extents(spiral)

	# El origin del pool debe coincidir con el visual completo.
	assert_float(neighbor_body.global_transform.origin.distance_to(visual_neighbor.origin)).is_less(0.02)
	assert_vector3(neighbor_box.extents).is_equal_approx(visual_extents, Vector3(0.001, 0.001, 0.001))
	# El pool sigue la orientación visual exacta para que la colisión coincida
	# con el mesh vecino.
	assert_float(neighbor_body.global_transform.basis.x.normalized().dot(visual_neighbor.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(neighbor_body.global_transform.basis.y.normalized().dot(visual_neighbor.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(neighbor_body.global_transform.basis.z.normalized().dot(visual_neighbor.basis.z.normalized())).is_greater_equal(0.999)

	# Raycast a lo largo de la normal local del slot: debe golpear el StaticBody del pool.
	var normal: Vector3 = neighbor_body.global_transform.basis.y.normalized()
	var from: Vector3 = neighbor_body.global_transform.origin + normal * 6.0
	var to: Vector3 = neighbor_body.global_transform.origin - normal * 6.0
	var hit: Dictionary = scene.get_world().direct_space_state.intersect_ray(from, to, [], 255)
	assert_bool(hit.has("collider")).is_true()
	assert_object(hit["collider"]).is_same(neighbor_body)

func test_test_scene_aligns_axial_up_to_ship_axis() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	rotator.spiral_blend = 0.0
	rotator.apply_selection()
	var plate_canonical: Transform = rotator.get_selected_plate_canonical_transform()
	var actual_global_up: Vector3 = (rotator.global_transform * plate_canonical).basis.y.normalized()

	assert_float(actual_global_up.dot(Vector3.UP)).is_greater_equal(0.999)

func test_test_scene_has_no_scene_script() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	assert_object(scene.get_script()).is_null()
	assert_object(scene.get_node_or_null("Pilot")).is_not_null()
	assert_object(scene.get_node_or_null("PhysicalTerrace/CollisionShape/Pilot")).is_null()

func test_test_scene_tracks_player_to_neighbor_plate_and_rebuilds_collisions() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	rotator.rotation_speed = 1000.0
	# Desactivar continuous_tracking para probar plate-tracking deterministamente.
	rotator.continuous_tracking = false
	rotator.auto_track_requires_floor_contact = false
	var player: Spatial = scene.get_node("Pilot")
	var spiral_index: int = rotator.get_selected_spiral_index()
	var next_plate: int = rotator.get_selected_plate_index() + 1
	var spiral: Spatial = rotator.get_platforms()[spiral_index]
	var target_global: Transform = rotator.global_transform * rotator.get_plate_canonical_transform(spiral, next_plate)
	player.global_transform.origin = target_global.origin + target_global.basis.y.normalized() * 8.0
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
	assert_int(rotator.get_generated_collision_count()).is_greater_equal(rotator.collision_pool_size - 4)

	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = rotator.get_active_collision_transform()
	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)



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

func test_gravity_world_partial_blend_mixes_down_and_radial_direction() -> void:
	var manager = auto_free(GravityWorldScript.new())
	manager.one_g_strength = 9.81
	manager.set_ship_axis(Vector3.ZERO, Vector3.UP)
	manager.set_centrifugal_reference_radius(10.0)
	manager.set_ship_angular_velocity(0.0)
	manager.set_gravity_blend(0.5)

	var gravity: Vector3 = manager.get_canonical_gravity(Vector3(20.0, 0.0, 0.0))
	var expected: Vector3 = (Vector3.DOWN * 9.81).linear_interpolate(Vector3.RIGHT * 19.62, 0.5)

	assert_float(gravity.distance_to(expected)).is_less(0.001)
	assert_float(manager.get_gravity_strength(Vector3(20.0, 0.0, 0.0))).is_equal_approx(expected.length(), 0.001)

func test_gravity_world_centrifugal_direction_matches_plate_down_near_center() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	var plate_canonical: Transform = rotator.get_selected_plate_canonical_transform()
	GravityWorld.set_gravity_blend(1.0)
	GravityWorld.set_ship_axis(Vector3.ZERO, Vector3.UP)
	GravityWorld.set_centrifugal_reference_radius(GravityWorld.get_axis_radius(plate_canonical.origin))
	GravityWorld.set_ship_angular_velocity(0.0)

	var gravity_direction: Vector3 = GravityWorld.get_canonical_gravity_direction(plate_canonical.origin)
	var plate_down: Vector3 = -plate_canonical.basis.y.normalized()

	assert_float(gravity_direction.dot(plate_down)).is_greater_equal(0.98)

func test_physical_terrace_stays_standard_up_in_centrifugal_mode() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	rotator.spiral_blend = 1.0
	rotator.apply_selection()
	GravityWorld.set_gravity_blend(1.0)

	var physical_terrace: StaticBody = scene.get_node("PhysicalTerrace")

	assert_float(physical_terrace.global_transform.basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)
	assert_float(rotator.get_selected_plate_global_transform().basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)

func test_continuous_tracking_keeps_player_outside_physical_terrace_tree() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	var physical_terrace: StaticBody = scene.get_node("PhysicalTerrace")
	var player: Spatial = scene.get_node("Pilot")
	rotator.continuous_tracking = true
	rotator.rotation_speed = 1000.0
	GravityWorld.set_gravity_blend(1.0)

	var player_before: Vector3 = player.global_transform.origin
	for _i in range(4):
		yield(get_tree(), "physics_frame")

	assert_bool(_is_descendant_of(player, physical_terrace)).is_false()
	assert_float(player.global_transform.origin.distance_to(player_before)).is_less(8.0)
	assert_float(physical_terrace.global_transform.basis.y.normalized().dot(Vector3.UP)).is_greater_equal(0.999)

func test_continuous_tracking_does_not_force_pool_update_every_frame() -> void:
	var rotator = auto_free(WorldRotatorScript.new())
	rotator.continuous_tracking = true
	rotator._has_transform_target = true
	rotator._target_global_transform = Transform(Basis(Vector3.RIGHT, 0.5), Vector3(10.0, 0.0, 0.0))

	assert_bool(rotator._is_pool_update_due()).is_false()

func test_collision_pool_reassignment_waits_until_center_moves_enough() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	for _i in range(3):
		yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	var player: Spatial = scene.get_node("Pilot")
	rotator.collision_reassign_min_distance = 30.0
	rotator._assign_pool_to_nearest_plates()

	assert_bool(rotator._pool_force_reassign).is_false()
	assert_bool(rotator._should_reassign_collision_pool()).is_false()

	player.global_transform.origin += rotator.global_transform.basis.x.normalized() * 5.0
	assert_bool(rotator._should_reassign_collision_pool()).is_false()

	player.global_transform.origin += rotator.global_transform.basis.x.normalized() * 40.0
	assert_bool(rotator._should_reassign_collision_pool()).is_true()

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

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var p: Node = node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false
