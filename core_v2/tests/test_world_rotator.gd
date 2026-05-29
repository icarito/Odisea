extends GdUnitTestSuite

const TestWorldRotatorScene = preload("res://core_v2/tests/TestWorldRotator.tscn")
const BaseTerraceScene = preload("res://core_v2/levels/BaseTerrace.tscn")
const OdiseaExteriorScene = preload("res://core_v2/levels/OdiseaExterior.tscn")
const WorldRotatorScene = preload("res://core_v2/components/WorldRotator.tscn")
const WorldRotatorScript = preload("res://core_v2/systems/WorldRotator.gd")
const GravityWorldScript = preload("res://core_v2/systems/GravityWorld.gd")
const PushableBoxV2Scene = preload("res://core_v2/components/PushableBoxV2.tscn")

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

func test_test_scene_streams_plate_content_outside_world_rotator() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator: Spatial = scene.get_node("WorldRotator")
	var stream: Spatial = scene.get_plate_content_stream()
	assert_object(stream).is_not_null()
	assert_bool(_is_descendant_of(stream, rotator)).is_false()

	var boxes: Array = scene.get_streamed_pushable_boxes()
	assert_int(boxes.size()).is_greater_equal(3)
	for box in boxes:
		assert_bool(_is_descendant_of(box, rotator)).is_false()
		assert_bool(_is_descendant_of(box, stream)).is_true()
		var slot: Spatial = stream.get_slot_for_node(box)
		assert_object(slot).is_not_null()
		var box_local: Transform = slot.global_transform.affine_inverse() * (box as Spatial).global_transform
		assert_float(box_local.origin.y).is_greater_equal(2.0)

func test_test_scene_world_rotator_has_no_physics_children() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	var rotator = scene.get_node("WorldRotator")
	assert_array(rotator.get_physics_child_violations()).is_empty()

func test_odisea_exterior_preserves_authored_spiral_blend_at_runtime() -> void:
	var scene = auto_free(OdiseaExteriorScene.instance())
	var rotator = scene.get_node("WorldRotator")
	rotator.spiral_blend = 0.35

	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	assert_float(rotator.spiral_blend).is_equal_approx(0.35, 0.001)

func test_odisea_exterior_keeps_neighbor_platform_collisions_in_flat_blend() -> void:
	var scene = auto_free(OdiseaExteriorScene.instance())
	var rotator = scene.get_node("WorldRotator")
	rotator.spiral_blend = 0.0

	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")

	assert_bool(rotator.centrifugal_current_plate_only_physics).is_false()
	assert_int(scene.get_generated_collision_count()).is_greater(0)

func test_streamed_pushable_boxes_keep_local_pose_when_slot_moves() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "idle_frame")

	var stream: Spatial = scene.get_plate_content_stream()
	var boxes: Array = scene.get_streamed_pushable_boxes()
	assert_int(boxes.size()).is_greater_equal(1)

	var box: RigidBody = boxes[0] as RigidBody
	assert_object(box).is_not_null()
	box.mode = RigidBody.MODE_KINEMATIC
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.sleeping = true

	var slot: Spatial = stream.get_slot_for_node(box)
	assert_object(slot).is_not_null()
	var local_before: Transform = slot.global_transform.affine_inverse() * box.global_transform

	var rotator: Spatial = scene.get_node("WorldRotator")
	var original: Transform = rotator.global_transform
	var rotated_basis: Basis = (Basis(Vector3.UP, deg2rad(35.0)) * original.basis).orthonormalized()
	rotator.global_transform = Transform(rotated_basis, original.origin)
	stream._sync_slot_transforms(0.0)
	yield(get_tree(), "physics_frame")

	var local_after: Transform = slot.global_transform.affine_inverse() * box.global_transform
	assert_float(local_after.origin.distance_to(local_before.origin)).is_less(0.02)
	assert_float(local_after.basis.y.normalized().dot(local_before.basis.y.normalized())).is_greater_equal(0.999)

func test_streamed_pushable_boxes_can_wake_to_rigidbody() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "idle_frame")

	var boxes: Array = scene.get_streamed_pushable_boxes()
	assert_int(boxes.size()).is_greater_equal(1)

	var box: RigidBody = boxes[0] as RigidBody
	assert_object(box).is_not_null()
	assert_int(box.mode).is_equal(RigidBody.MODE_KINEMATIC)
	assert_bool(box.is_in_group("pushable")).is_true()

	if box.has_method("wake_up"):
		box.wake_up()

	assert_int(box.mode).is_equal(RigidBody.MODE_RIGID)
	assert_bool(box.sleeping).is_false()

func test_streamed_pushable_boxes_can_move_when_forced() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "idle_frame")

	var boxes: Array = scene.get_streamed_pushable_boxes()
	assert_int(boxes.size()).is_greater_equal(1)

	var box: RigidBody = boxes[0] as RigidBody
	assert_object(box).is_not_null()
	var stream: Spatial = scene.get_plate_content_stream()
	var slot: Spatial = stream.get_slot_for_node(box)
	assert_object(slot).is_not_null()

	var start_local: Vector3 = slot.global_transform.affine_inverse().xform(box.global_transform.origin)
	for _i in range(20):
		box.set_external_velocity(Vector3.RIGHT * 3.0)
		yield(get_tree(), "physics_frame")

	var end_local: Vector3 = slot.global_transform.affine_inverse().xform(box.global_transform.origin)
	assert_float(end_local.distance_to(start_local)).is_greater(0.05)

func test_streamed_rigid_boxes_preserve_slot_local_pose_when_slot_moves() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "idle_frame")

	var boxes: Array = scene.get_streamed_pushable_boxes()
	assert_int(boxes.size()).is_greater_equal(1)

	var box: RigidBody = boxes[0] as RigidBody
	assert_object(box).is_not_null()
	if box.has_method("wake_up"):
		box.call("wake_up")
	box.mode = RigidBody.MODE_RIGID
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO

	var stream: Spatial = scene.get_plate_content_stream()
	var slot: Spatial = stream.get_slot_for_node(box)
	assert_object(slot).is_not_null()

	var start_global: Transform = box.global_transform
	var start_local: Transform = slot.global_transform.affine_inverse() * box.global_transform
	var rotator: Spatial = scene.get_node("WorldRotator")
	var delta_basis := Basis(Vector3.FORWARD, deg2rad(12.0))
	rotator.global_transform = Transform(
		delta_basis * rotator.global_transform.basis,
		rotator.global_transform.origin + Vector3(5.0, 1.5, -2.0)
	)
	stream._sync_slot_transforms(1.0 / 60.0)

	var end_local: Transform = slot.global_transform.affine_inverse() * box.global_transform
	assert_float(box.global_transform.origin.distance_to(start_global.origin)).is_greater(0.1)
	assert_float(end_local.origin.distance_to(start_local.origin)).is_less(0.02)
	assert_float(end_local.basis.x.normalized().dot(start_local.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(end_local.basis.y.normalized().dot(start_local.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(end_local.basis.z.normalized().dot(start_local.basis.z.normalized())).is_greater_equal(0.999)

func test_pushable_box_projects_external_velocity_onto_support_plane() -> void:
	var box: RigidBody = auto_free(PushableBoxV2Scene.instance())
	add_child(box)
	yield(get_tree(), "idle_frame")

	box._has_support_contact = true
	box._support_normal = Vector3(0.0, 1.0, 1.0).normalized()

	var projected: Vector3 = box._project_vector_onto_plane(Vector3(0.0, 0.0, 3.0), box._support_normal)
	assert_float(projected.dot(box._support_normal)).is_less(0.001)
	assert_float(projected.length()).is_greater(0.1)

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

func test_test_scene_keeps_only_current_plate_physics_in_centrifugal_mode() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	var rotator = scene.get_node("WorldRotator")
	rotator.centrifugal_current_plate_only_physics = true
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	assert_bool(rotator.centrifugal_current_plate_only_physics).is_true()
	assert_object(scene.get_node_or_null("GeneratedTerraceCollisions")).is_not_null()
	assert_int(scene.get_generated_collision_count()).is_equal(0)

	for body in rotator._collision_pool:
		if is_instance_valid(body):
			assert_int(int(body.get_meta("spiral_index"))).is_equal(-1)
			assert_int(int(body.get_meta("plate_index"))).is_equal(-1)

	var active_body: StaticBody = scene.get_active_collision_body()
	assert_object(active_body).is_not_null()
	var from: Vector3 = active_body.global_transform.origin + active_body.global_transform.basis.y.normalized() * 6.0
	var to: Vector3 = active_body.global_transform.origin - active_body.global_transform.basis.y.normalized() * 6.0
	var hit: Dictionary = scene.get_world().direct_space_state.intersect_ray(from, to, [], 255)
	assert_bool(hit.has("collider")).is_true()
	assert_object(hit["collider"]).is_same(active_body)

func test_collision_pool_preserves_plate_slot_when_distance_order_changes() -> void:
	var scene = auto_free(TestWorldRotatorScene.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var rotator = scene.get_node("WorldRotator")
	rotator.centrifugal_current_plate_only_physics = false
	var spiral_index: int = rotator.get_selected_spiral_index()
	var plate_index: int = rotator.get_selected_plate_index() + 1
	var spiral: Spatial = rotator.get_platforms()[spiral_index]
	rotator._assign_pool_to_nearest_plates()

	var body_before: StaticBody = _find_pool_body(rotator, spiral_index, plate_index)
	assert_object(body_before).is_not_null()

	var player: Spatial = scene.get_node("Pilot")
	var nearby_plate: int = plate_index + 2
	var target_global: Transform = rotator.global_transform * rotator.get_plate_canonical_transform(spiral, nearby_plate)
	player.global_transform.origin = target_global.origin + target_global.basis.y.normalized() * 4.0
	rotator._assign_pool_to_nearest_plates()

	var body_after: StaticBody = _find_pool_body(rotator, spiral_index, plate_index)
	assert_object(body_after).is_same(body_before)

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
	rotator.centrifugal_current_plate_only_physics = true
	rotator.rotation_speed = 1000.0
	rotator.rotation_frozen = false
	# Desactivar continuous_tracking para probar plate-tracking deterministamente.
	rotator.continuous_tracking = false
	rotator.auto_track_requires_floor_contact = false
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
	assert_int(scene.get_generated_collision_count()).is_equal(0)

	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = rotator.get_active_collision_transform()
	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.x.normalized().dot(target.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(selected.basis.z.normalized().dot(target.basis.z.normalized())).is_greater_equal(0.999)

func test_world_rotator_bootstrap_selects_nearest_plate_on_ready() -> void:
	var root: Spatial = auto_free(Spatial.new())
	root.name = "BootstrapRoot"
	add_child(root)

	var physical_terrace := StaticBody.new()
	physical_terrace.name = "Terrace"
	root.add_child(physical_terrace)

	var physical_shape := CollisionShape.new()
	physical_shape.name = "CollisionShape"
	var box_shape := BoxShape.new()
	box_shape.extents = Vector3(40.0, 1.0, 40.0)
	physical_shape.shape = box_shape
	physical_terrace.add_child(physical_shape)

	var pilot := Spatial.new()
	pilot.name = "Pilot"
	pilot.transform.origin = Vector3(0.0, 3.0, 3.0)
	root.add_child(pilot)

	var rotator = WorldRotatorScene.instance()
	rotator.name = "WorldRotator"
	rotator.spiral_blend = 1.0
	rotator.select_nearest_plate_on_ready = true
	rotator.snap_initial_selection = true
	rotator.physical_terrace_path = NodePath("../Terrace")
	rotator.tracking_target_path = NodePath("../Pilot")
	rotator.auto_track_target_plate = true
	rotator.auto_track_requires_floor_contact = true
	rotator.continuous_tracking = true
	rotator.collision_pool_size = 16
	root.add_child(rotator)

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	assert_int(rotator.get_selected_spiral_index()).is_greater_equal(0)
	assert_int(rotator.get_selected_plate_index()).is_greater_equal(0)
	assert_object(rotator._get_tracking_target()).is_same(pilot)

	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = physical_terrace.global_transform
	assert_float(selected.origin.distance_to(target.origin)).is_less(0.02)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)
	_assert_no_handoff_collision_metadata(rotator)

func test_world_rotator_scene_anchor_places_reference_on_configured_plate() -> void:
	var root: Spatial = auto_free(Spatial.new())
	root.name = "SceneAnchorRoot"
	add_child(root)

	var rotator = WorldRotatorScene.instance()
	rotator.name = "WorldRotator"
	rotator.current_platform = NodePath("")
	rotator.auto_select_first_platform = false
	rotator.spiral_blend = 1.0
	rotator.rotation_frozen = true
	rotator.scene_anchor_content_path = NodePath("Terrace")
	rotator.scene_anchor_reference_path = NodePath("Terrace/Marker")
	rotator.scene_anchor_spiral_index = 1
	rotator.scene_anchor_plate_index = 12
	root.add_child(rotator)

	var terrace := Spatial.new()
	terrace.name = "Terrace"
	terrace.transform = Transform(Basis.IDENTITY, Vector3(10.0, -1.0, -5.0))
	rotator.add_child(terrace)

	var marker := Spatial.new()
	marker.name = "Marker"
	marker.transform = Transform(Basis.IDENTITY, Vector3(3.0, 2.0, 4.0))
	terrace.add_child(marker)

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var platforms: Array = rotator.get_platforms()
	assert_int(platforms.size()).is_greater(1)
	var expected: Transform = rotator.global_transform * rotator.get_plate_canonical_transform(platforms[1], 12)
	assert_float(marker.global_transform.origin.distance_to(expected.origin)).is_less(0.05)
	assert_float(marker.global_transform.basis.y.normalized().dot(expected.basis.y.normalized())).is_greater_equal(0.999)

func test_continuous_tracking_applies_full_correction_in_same_physics_tick() -> void:
	var root: Spatial = auto_free(Spatial.new())
	root.name = "ContinuousTrackingRoot"
	add_child(root)

	var pilot := Spatial.new()
	pilot.name = "Pilot"
	pilot.transform.origin = Vector3(300.0, 4.0, 0.0)
	root.add_child(pilot)

	var rotator = WorldRotatorScript.new()
	rotator.name = "WorldRotator"
	rotator.rotation_speed = 0.001
	rotator.airborne_rotation_factor = 0.0
	rotator.auto_select_first_platform = false
	rotator.auto_track_target_plate = false
	rotator.continuous_tracking = true
	rotator.tracking_target_path = NodePath("../Pilot")
	root.add_child(rotator)
	yield(get_tree(), "idle_frame")

	if has_node("/root/GravityWorld"):
		GravityWorld.set_ship_axis(Vector3.ZERO, Vector3.UP)
		GravityWorld.set_gravity_blend(1.0)

	var canonical_before: Vector3 = rotator.to_canonical(pilot.global_transform.origin)
	rotator._physics_process(1.0 / 60.0)

	var corrected_global: Vector3 = rotator.from_canonical(canonical_before)
	var corrected_up: Vector3 = rotator.global_transform.basis.xform(Vector3.LEFT).normalized()
	assert_float(corrected_global.distance_to(pilot.global_transform.origin)).is_less(0.02)
	assert_float(corrected_up.dot(Vector3.UP)).is_greater_equal(0.999)

	if has_node("/root/GravityWorld"):
		GravityWorld.set_gravity_blend(0.0)

func test_baseterrace_world_rotator_uses_pilot_and_centrifugal_terrace_anchor() -> void:
	var scene = auto_free(BaseTerraceScene.instance())
	add_child(scene)

	var initial_pilot: Spatial = scene.get_node("Pilot")
	var initial_crio_start: Spatial = scene.get_node("WorldRotator/Terrace/Building/CrioPod START")
	assert_float(
		initial_pilot.global_transform.origin.distance_to(initial_crio_start.global_transform.origin + Vector3(-0.0003, 1.08256, 0.1851))
	).is_less(0.05)

	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	# Terrace is now a child of WorldRotator so it rotates with the centrifuge.
	var terrace: Spatial = scene.get_node("WorldRotator/Terrace")
	var physical_terrace: StaticBody = scene.get_node("PhysicalTerrace")
	var pilot: Spatial = scene.get_node("Pilot")
	var rotator = scene.get_node("WorldRotator")
	var crio_start: Spatial = scene.get_node("WorldRotator/Terrace/Building/CrioPod START")

	assert_object(terrace).is_not_null()
	assert_object(physical_terrace).is_not_null()
	assert_object(pilot).is_not_null()
	assert_object(crio_start).is_not_null()
	assert_object(scene.get_node_or_null("WorldRotator/Terrace/Pilot")).is_null()
	assert_object(scene.get_node_or_null("WorldRotator/Terrace/Building/CrioPod START/Pilot")).is_null()
	assert_object(scene.get_node_or_null("Terrace/WorldRotator")).is_null()
	assert_int(_count_nodes_named(scene, "Pilot")).is_equal(1)
	assert_int(_count_player_group_members_under(scene)).is_equal(1)
	assert_bool(terrace.use_collision).is_false()
	assert_object(physical_terrace.get_node_or_null("CollisionShape")).is_not_null()
	assert_object(physical_terrace.get_node_or_null("MeshInstance")).is_null()

	assert_object(rotator._get_tracking_target()).is_same(pilot)
	assert_str(str(rotator.tracking_target_path)).is_equal("../Pilot")
	assert_str(str(rotator.physical_terrace_path)).is_equal("../PhysicalTerrace")
	assert_object(rotator.get_active_collision_body()).is_same(physical_terrace)
	assert_bool(rotator.select_nearest_plate_on_ready).is_true()
	assert_bool(rotator.snap_initial_selection).is_true()
	assert_bool(rotator.auto_track_target_plate).is_true()
	assert_bool(rotator.auto_track_requires_floor_contact).is_true()
	assert_int(rotator.target_plate_query_interval).is_equal(3)
	assert_bool(rotator.continuous_tracking).is_true()
	assert_str(str(rotator.scene_anchor_content_path)).is_equal("Terrace")
	assert_str(str(rotator.scene_anchor_reference_path)).is_equal("Terrace")
	assert_bool(rotator.scene_anchor_use_selected_plate_on_ready).is_true()
	assert_float(rotator.scene_anchor_offset.y).is_equal_approx(0.0, 0.001)
	assert_float(rotator.spiral_blend).is_equal_approx(1.0, 0.001)
	assert_int(rotator.collision_pool_size).is_equal(16)
	assert_bool(rotator.centrifugal_current_plate_only_physics).is_false()
	assert_int(rotator.get_selected_spiral_index()).is_greater_equal(0)
	assert_int(rotator.get_selected_plate_index()).is_greater_equal(0)

	var selected: Transform = rotator.get_selected_plate_global_transform()
	var target: Transform = physical_terrace.global_transform
	assert_float(selected.origin.distance_to(target.origin)).is_less(0.05)
	assert_float(selected.basis.y.normalized().dot(target.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(terrace.global_transform.origin.distance_to(selected.origin)).is_less(0.05)
	assert_float(terrace.global_transform.basis.y.normalized().dot(selected.basis.y.normalized())).is_greater_equal(0.999)
	assert_float(crio_start.global_transform.basis.y.normalized().dot(selected.basis.y.normalized())).is_greater_equal(0.999)
	_assert_no_handoff_collision_metadata(rotator)


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

func _assert_no_handoff_collision_metadata(rotator: Node) -> void:
	for body in rotator._collision_pool:
		if is_instance_valid(body):
			assert_bool(body.has_meta("world_rotator_handoff_collision")).is_false()

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current: Node = node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false

func _count_nodes_named(root: Node, node_name: String) -> int:
	var count := 0
	if root.name == node_name:
		count += 1
	for child in root.get_children():
		count += _count_nodes_named(child, node_name)
	return count

func _count_player_group_members_under(root: Node) -> int:
	var count := 0
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and (player == root or root.is_a_parent_of(player)):
			count += 1
	return count

func _find_pool_body(rotator: Node, spiral_index: int, plate_index: int) -> StaticBody:
	for body in rotator._collision_pool:
		if is_instance_valid(body) \
				and int(body.get_meta("spiral_index")) == spiral_index \
				and int(body.get_meta("plate_index")) == plate_index:
			return body
	return null
