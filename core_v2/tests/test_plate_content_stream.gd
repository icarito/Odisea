extends GdUnitTestSuite

const WorldRotatorScene = preload("res://core_v2/components/WorldRotator.tscn")
const PlateContentStreamScript = preload("res://core_v2/systems/PlateContentStream.gd")
const PlateSlotConfigScript = preload("res://core_v2/systems/PlateSlotConfig.gd")

func test_slot_matches_plate_global_transform() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var rotator: Spatial = setup["rotator"]
	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_static_content_scene("ContentA"))
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	assert_object(slot).is_not_null()

	var expected: Transform = _get_plate_global_transform(rotator, 0, 12)
	assert_float(slot.global_transform.origin.distance_to(expected.origin)).is_less(0.02)
	assert_float(slot.global_transform.basis.y.normalized().dot(expected.basis.y.normalized())).is_greater_equal(0.999)

func test_slot_follows_world_rotator_rotation() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var rotator: Spatial = setup["rotator"]
	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_static_content_scene("ContentA"))
	yield(get_tree(), "physics_frame")

	rotator.global_transform = Transform(Basis(Vector3.UP, deg2rad(90.0)), Vector3.ZERO)
	stream._sync_slot_transforms()
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	var expected: Transform = _get_plate_global_transform(rotator, 0, 12)
	assert_object(slot).is_not_null()
	assert_float(slot.global_transform.origin.distance_to(expected.origin)).is_less(0.02)
	assert_float(slot.global_transform.basis.x.normalized().dot(expected.basis.x.normalized())).is_greater_equal(0.999)
	assert_float(slot.global_transform.basis.y.normalized().dot(expected.basis.y.normalized())).is_greater_equal(0.999)

func test_static_body_child_has_functional_collision() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var root: Spatial = setup["root"]
	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_static_content_scene("RaycastContent"))
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	assert_object(slot).is_not_null()
	var body: StaticBody = slot.get_node_or_null("RaycastContent/ContentBody") as StaticBody
	assert_object(body).is_not_null()

	var from: Vector3 = slot.global_transform.xform(Vector3(0.0, 4.0, 0.0))
	var to: Vector3 = slot.global_transform.xform(Vector3(0.0, 0.0, 0.0))
	var hit: Dictionary = root.get_world().direct_space_state.intersect_ray(from, to, [], 255)
	assert_bool(hit.has("collider")).is_true()
	if not hit.has("collider"):
		return
	assert_object(hit["collider"]).is_same(body)

func test_centrifugal_stream_only_enables_physics_on_selected_plate() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var rotator: Spatial = setup["rotator"]
	var stream: Spatial = setup["stream"]
	assert_bool(rotator.select_terrace_plate(0, 12, null, true)).is_true()
	stream.assign_scene(0, 12, _make_static_content_scene("CurrentContent"))
	stream.assign_scene(0, 13, _make_static_content_scene("NeighborContent"))
	yield(get_tree(), "physics_frame")

	var current_slot: Spatial = stream.get_slot(0, 12)
	var neighbor_slot: Spatial = stream.get_slot(0, 13)
	assert_object(current_slot).is_not_null()
	assert_object(neighbor_slot).is_not_null()
	var current_body: StaticBody = current_slot.get_node_or_null("CurrentContent/ContentBody") as StaticBody
	var neighbor_body: StaticBody = neighbor_slot.get_node_or_null("NeighborContent/ContentBody") as StaticBody
	assert_object(current_body).is_not_null()
	assert_object(neighbor_body).is_not_null()
	assert_int(current_body.collision_layer).is_equal(1)
	assert_int(neighbor_body.collision_layer).is_equal(0)
	assert_int(neighbor_body.collision_mask).is_equal(0)

	assert_bool(rotator.select_terrace_plate(0, 13, null, true)).is_true()
	stream._refresh_active_slots()
	stream._sync_physics_activation_for_slots()

	assert_int(current_body.collision_layer).is_equal(0)
	assert_int(current_body.collision_mask).is_equal(0)
	assert_int(neighbor_body.collision_layer).is_equal(1)
	assert_int(neighbor_body.collision_mask).is_equal(1)

func test_reassigning_scene_replaces_active_slot_child() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_marker_scene("ContentA"))
	yield(get_tree(), "physics_frame")
	var slot_before: Spatial = stream.get_slot(0, 12)
	assert_object(slot_before).is_not_null()
	assert_object(slot_before.get_node_or_null("ContentA")).is_not_null()

	stream.assign_scene(0, 12, _make_marker_scene("ContentB"))
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")
	var slot_after: Spatial = stream.get_slot(0, 12)
	assert_object(slot_after).is_same(slot_before)
	assert_object(slot_after.get_node_or_null("ContentA")).is_null()
	assert_object(slot_after.get_node_or_null("ContentB")).is_not_null()

func test_assign_scene_applies_world_spawn_offset_to_streamed_content() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_marker_scene("OffsetContent"), Vector3(0.0, 0.3, 0.0))
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	assert_object(slot).is_not_null()
	var content: Spatial = slot.get_node_or_null("OffsetContent") as Spatial
	assert_object(content).is_not_null()
	assert_float(content.global_transform.origin.distance_to(slot.global_transform.origin + Vector3(0.0, 0.3, 0.0))).is_less(0.02)

func test_assign_scene_applies_context_metadata_to_instanced_root() -> void:
	var setup: Dictionary = _build_stream_setup()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var stream: Spatial = setup["stream"]
	stream.assign_scene(0, 12, _make_marker_scene("ContextContent"), Vector3.ZERO, {"dome_id": "dome_02"})
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	assert_object(slot).is_not_null()
	var content: Node = slot.get_node_or_null("ContextContent")
	assert_object(content).is_not_null()
	assert_bool(content.has_meta("dome_id")).is_true()
	assert_str(String(content.get_meta("dome_id"))).is_equal("dome_02")

func test_active_slots_keep_key_binding_when_distance_order_changes() -> void:
	var setup: Dictionary = _build_stream_setup()
	var stream: Spatial = setup["stream"]
	stream.slot_pool_size = 2
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	_move_pilot_to_plate(setup, 0, 11)
	stream.assign_scene(0, 11, _make_marker_scene("ContentA"))
	stream.assign_scene(0, 12, _make_marker_scene("ContentB"))
	yield(get_tree(), "physics_frame")

	var slot_a_before: Spatial = stream.get_slot(0, 11)
	var slot_b_before: Spatial = stream.get_slot(0, 12)
	assert_object(slot_a_before).is_not_null()
	assert_object(slot_b_before).is_not_null()
	var marker_a_before: Node = slot_a_before.get_node_or_null("ContentA/Marker")
	var marker_b_before: Node = slot_b_before.get_node_or_null("ContentB/Marker")
	assert_object(marker_a_before).is_not_null()
	assert_object(marker_b_before).is_not_null()

	_move_pilot_to_plate(setup, 0, 12)
	stream._refresh_active_slots()
	yield(get_tree(), "physics_frame")

	assert_object(stream.get_slot(0, 11)).is_same(slot_a_before)
	assert_object(stream.get_slot(0, 12)).is_same(slot_b_before)
	assert_object(slot_a_before.get_node_or_null("ContentA/Marker")).is_same(marker_a_before)
	assert_object(slot_b_before.get_node_or_null("ContentB/Marker")).is_same(marker_b_before)

func test_plate_slot_config_assigns_scene_on_ready() -> void:
	var root: Spatial = auto_free(Spatial.new())
	root.name = "PlateSlotConfigTestRoot"
	add_child(root)

	var pilot := Spatial.new()
	pilot.name = "Pilot"
	pilot.translation = Vector3(0.0, 3.0, 3.0)
	root.add_child(pilot)

	var rotator = WorldRotatorScene.instance()
	rotator.name = "WorldRotator"
	rotator.current_platform = NodePath("")
	rotator.auto_select_first_platform = false
	rotator.spiral_blend = 1.0
	rotator.rotation_frozen = true
	rotator.tracking_target_path = NodePath("../Pilot")
	root.add_child(rotator)

	var stream = PlateContentStreamScript.new()
	stream.name = "PlateContentRoot"
	stream.rotator_path = NodePath("../WorldRotator")
	stream.tracking_target_path = NodePath("../Pilot")
	stream.slot_pool_size = 4

	var config = PlateSlotConfigScript.new()
	config.name = "PlateSlotConfig_0_12"
	config.spiral_idx = 0
	config.plate_idx = 12
	config.content_scene = _make_marker_scene("ConfiguredContent")
	stream.add_child(config)
	root.add_child(stream)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "physics_frame")

	var slot: Spatial = stream.get_slot(0, 12)
	assert_object(slot).is_not_null()
	assert_object(slot.get_node_or_null("ConfiguredContent/Marker")).is_not_null()

func _build_stream_setup() -> Dictionary:
	var root: Spatial = auto_free(Spatial.new())
	root.name = "PlateContentStreamTestRoot"
	add_child(root)

	var pilot := Spatial.new()
	pilot.name = "Pilot"
	pilot.translation = Vector3(0.0, 3.0, 3.0)
	root.add_child(pilot)

	var rotator = WorldRotatorScene.instance()
	rotator.name = "WorldRotator"
	rotator.current_platform = NodePath("")
	rotator.auto_select_first_platform = false
	rotator.spiral_blend = 1.0
	rotator.rotation_frozen = true
	rotator.tracking_target_path = NodePath("../Pilot")
	rotator.collision_pool_size = 4
	root.add_child(rotator)

	var stream = PlateContentStreamScript.new()
	stream.name = "PlateContentRoot"
	stream.rotator_path = NodePath("../WorldRotator")
	stream.tracking_target_path = NodePath("../Pilot")
	stream.slot_pool_size = 4
	stream.slot_update_interval = 1
	root.add_child(stream)

	return {
		"root": root,
		"pilot": pilot,
		"rotator": rotator,
		"stream": stream
	}

func _get_plate_global_transform(rotator: Spatial, spiral_idx: int, plate_idx: int) -> Transform:
	var platforms: Array = rotator.get_platforms()
	assert_int(platforms.size()).is_greater(spiral_idx)
	var spiral: Spatial = platforms[spiral_idx]
	return rotator.global_transform * rotator.get_plate_canonical_transform(spiral, plate_idx)

func _move_pilot_to_plate(setup: Dictionary, spiral_idx: int, plate_idx: int) -> void:
	var rotator: Spatial = setup["rotator"]
	var pilot: Spatial = setup["pilot"]
	var plate_tx: Transform = _get_plate_global_transform(rotator, spiral_idx, plate_idx)
	pilot.global_transform.origin = plate_tx.origin + plate_tx.basis.y.normalized() * 3.0

func _make_static_content_scene(scene_name: String) -> PackedScene:
	var root := Spatial.new()
	root.name = scene_name

	var body := StaticBody.new()
	body.name = "ContentBody"
	body.collision_layer = 1
	body.collision_mask = 1
	body.translation = Vector3(0.0, 2.0, 0.0)
	root.add_child(body)
	body.owner = root

	var shape := CollisionShape.new()
	shape.name = "CollisionShape"
	var box := BoxShape.new()
	box.extents = Vector3(1.5, 0.5, 1.5)
	shape.shape = box
	body.add_child(shape)
	shape.owner = root

	var packed := PackedScene.new()
	assert_int(packed.pack(root)).is_equal(OK)
	root.free()
	return packed

func _make_marker_scene(scene_name: String) -> PackedScene:
	var root := Spatial.new()
	root.name = scene_name
	var marker := Spatial.new()
	marker.name = "Marker"
	root.add_child(marker)
	marker.owner = root

	var packed := PackedScene.new()
	assert_int(packed.pack(root)).is_equal(OK)
	root.free()
	return packed
