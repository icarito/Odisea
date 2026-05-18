extends GdUnitTestSuite

const ASSETS := [
	{
		"scene": "res://core_v2/props/scifi_doors/DoorDoubleSidewaysV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/DoorDoubleSidewaysV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_doors/DoorSingleVerticalV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/DoorSingleVerticalV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_doors/DoorDoubleVerticalV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/DoorDoubleVerticalV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiWorkLightV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiWorkLightV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiWorkLightTripodV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiWorkLightTripodV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiWallSconceV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiWallSconceV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiPathMarkerV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiPathMarkerV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiPathMarkerArrowV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiPathMarkerArrowV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiRecessedFloorLightV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiRecessedFloorLightV2_point_class.tres",
	},
	{
		"scene": "res://core_v2/props/scifi_lights/SciFiRecessedWallLightV2.tscn",
		"point_class": "res://core_v2/qodot_fgd/props/SciFiRecessedWallLightV2_point_class.tres",
	},
]

func test_new_props_follow_interactable_contract_and_match_point_class_size():
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	yield(get_tree(), "idle_frame")

	for entry in ASSETS:
		var packed: PackedScene = load(entry["scene"]) as PackedScene
		assert_object(packed).is_not_null()

		var prop: Node = auto_free(packed.instance())
		host.add_child(prop)
		yield(get_tree(), "idle_frame")

		assert_bool(prop.has_method("interact")).is_true()
		assert_bool(prop.has_method("set_active")).is_true()
		assert_bool(prop.has_method("get_snapshot")).is_true()
		assert_bool(prop.has_method("restore_snapshot")).is_true()
		assert_bool(prop.is_in_group("replay_sync")).is_true()

		prop.set_active(true, true)
		assert_bool(prop.is_active).is_true()
		prop.set_active(false, true)
		assert_bool(prop.is_active).is_false()

		if not (prop is CollisionObject):
			assert_bool(_has_interaction_proxy(prop)).is_true()

		var point_class: Resource = load(entry["point_class"])
		assert_object(point_class).is_not_null()

		var meta = point_class.get("meta_properties")
		assert_bool(typeof(meta) == TYPE_DICTIONARY).is_true()
		assert_bool(meta.has("size")).is_true()

		var point_size: AABB = meta["size"]
		# In FGD point classes, the size property contains:
		# position: the minimum bounds (min_x, min_y, min_z)
		# size: the maximum bounds (max_x, max_y, max_z)
		# So the actual size in map units is max - min (which is size - position)
		var real_size_map_units = point_size.size - point_size.position
		
		# Map Qodot/TrenchBroom coordinates to Godot coordinate system and scale to meters:
		# Godot X <- TrenchBroom Y
		# Godot Y <- TrenchBroom Z
		# Godot Z <- TrenchBroom X
		var mapped_size_meters = Vector3(
			real_size_map_units.y * 0.0625,
			real_size_map_units.z * 0.0625,
			real_size_map_units.x * 0.0625
		)
		var scene_bounds: AABB = _compute_scene_visual_bounds(prop)

		assert_bool(mapped_size_meters.x >= scene_bounds.size.x * 0.95).is_true()
		assert_bool(mapped_size_meters.y >= scene_bounds.size.y * 0.95).is_true()
		assert_bool(mapped_size_meters.z >= scene_bounds.size.z * 0.95).is_true()

		# Keep TrenchBroom handles reasonably tight to the actual prop volume.
		assert_bool(mapped_size_meters.x <= scene_bounds.size.x * 4.0).is_true()
		assert_bool(mapped_size_meters.y <= scene_bounds.size.y * 4.0).is_true()
		assert_bool(mapped_size_meters.z <= max(0.8, scene_bounds.size.z * 4.0)).is_true()

func _has_interaction_proxy(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionObject and child.has_method("interact"):
			return true
		if _has_interaction_proxy(child):
			return true
	return false

func _compute_scene_visual_bounds(node: Node) -> AABB:
	var bounds: Array = _collect_visual_bounds(node)
	if bounds.empty():
		return AABB(Vector3.ZERO, Vector3.ONE * 0.1)
	var merged: AABB = bounds[0]
	for i in range(1, bounds.size()):
		merged = merged.merge(bounds[i])
	return merged

func _collect_visual_bounds(node: Node) -> Array:
	var bounds: Array = []
	for child in node.get_children():
		if child is MeshInstance or child is CSGShape:
			bounds.append(child.get_transformed_aabb())
		bounds.append_array(_collect_visual_bounds(child))
	return bounds
