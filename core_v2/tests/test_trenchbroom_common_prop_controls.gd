extends GdUnitTestSuite

func test_all_prop_point_class_resources_expose_common_controls():
	var dir := Directory.new()
	var err := dir.open("res://core_v2/qodot_fgd/props")
	assert_int(err).is_equal(OK)

	err = dir.list_dir_begin(true, true)
	assert_int(err).is_equal(OK)

	var checked := 0
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with("_point_class.tres"):
			var point_class: Resource = load("res://core_v2/qodot_fgd/props/%s" % file_name)
			assert_object(point_class).is_not_null()
			var props: Dictionary = point_class.get("class_properties")
			assert_bool(props.has("is_interactable")).is_true()
			assert_bool(props.has("enable_shadows")).is_true()
			checked += 1
		file_name = dir.get_next()

	dir.list_dir_end()
	assert_int(checked).is_greater(0)

func test_qodot_fgd_prop_and_light_classes_expose_common_controls():
	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	var blocks := _collect_custom_point_class_blocks(text)
	assert_int(blocks.size()).is_greater(0)

	for classname in blocks.keys():
		var body: String = blocks[classname]
		assert_bool(body.find("is_interactable(") >= 0).is_true()
		assert_bool(body.find("enable_shadows(") >= 0).is_true()

func test_trenchbroom_work_light_bounds_are_floor_aligned_z_up():
	var work_light: Resource = load("res://core_v2/qodot_fgd/props/SciFiWorkLightV2_point_class.tres")
	var tripod: Resource = load("res://core_v2/qodot_fgd/props/SciFiWorkLightTripodV2_point_class.tres")
	assert_object(work_light).is_not_null()
	assert_object(tripod).is_not_null()

	var work_light_size: AABB = work_light.get("meta_properties")["size"]
	var tripod_size: AABB = tripod.get("meta_properties")["size"]

	assert_vector3(work_light_size.position).is_equal(Vector3(-6, -6, 0))
	assert_vector3(work_light_size.size).is_equal(Vector3(6, 6, 18))
	assert_vector3(tripod_size.position).is_equal(Vector3(-13, -13, 0))
	assert_vector3(tripod_size.size).is_equal(Vector3(13, 13, 38))

	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	assert_bool(text.find("size(-6 -6 0, 6 6 18) = light_work") >= 0).is_true()
	assert_bool(text.find("size(-13 -13 0, 13 13 38) = light_work_tripod") >= 0).is_true()

func test_trenchbroom_work_lights_expose_native_rotation_controls():
	for path in [
		"res://core_v2/qodot_fgd/props/SciFiWorkLightV2_point_class.tres",
		"res://core_v2/qodot_fgd/props/SciFiWorkLightTripodV2_point_class.tres",
	]:
		var point_class: Resource = load(String(path))
		assert_object(point_class).is_not_null()
		var props: Dictionary = point_class.get("class_properties")
		assert_bool(props.has("angle")).is_true()
		assert_bool(props.has("angles")).is_true()

	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	for classname in ["light_work", "light_work_tripod"]:
		var block := _extract_point_class_block(text, String(classname))
		assert_bool(block != "").is_true()
		assert_bool(block.find("angle(angle) : \"Yaw rotation in degrees\"") >= 0).is_true()
		assert_bool(block.find("angles(string) : \"Pitch Yaw Roll rotation in degrees\"") >= 0).is_true()

func test_qodot_applies_work_light_angle_from_trenchbroom_source():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.entity_definitions = qodot_map.entity_fgd.get_entity_definitions()

	var packed: PackedScene = load("res://core_v2/props/scifi_lights/SciFiWorkLightTripodV2.tscn")
	assert_object(packed).is_not_null()
	var tripod: Spatial = auto_free(packed.instance())
	qodot_map.add_child(tripod)

	qodot_map.entity_nodes = [tripod]
	qodot_map.entity_dicts = [{
		"properties": {
			"classname": "light_work_tripod",
			"angle": "90"
		},
		"_source_property_keys": {
			"classname": true,
			"angle": true
		},
		"_source_has_angle": true,
		"_source_has_full_rotation": false
	}]

	qodot_map.apply_properties()
	assert_float(tripod.rotation_degrees.y).is_equal_approx(-90.0, 0.001)

func test_qodot_full_build_applies_work_light_angle_from_map_file():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://core_v2/tests/fixtures/work_light_angle_90.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()
	yield(get_tree(), "idle_frame")

	var tripod: Spatial = qodot_map.find_node("entity_1_light_work_tripod", true, false)
	assert_object(tripod).is_not_null()
	assert_float(tripod.rotation_degrees.y).is_equal_approx(-90.0, 0.001)

func test_qodot_full_build_preserves_crio_work_light_angle_from_source_map():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://maps/crio.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()
	yield(get_tree(), "idle_frame")

	var tripod: Spatial = qodot_map.find_node("entity_4_light_work_tripod", true, false)
	assert_object(tripod).is_not_null()
	assert_float(abs(tripod.rotation_degrees.y)).is_equal_approx(90.0, 0.001)

func test_trenchbroom_floor_hatch_bounds_match_scene_footprint():
	var hatch: Resource = load("res://core_v2/qodot_fgd/props/FloorHatch_point_class.tres")
	assert_object(hatch).is_not_null()

	var hatch_size: AABB = hatch.get("meta_properties")["size"]
	assert_vector3(hatch_size.position).is_equal(Vector3(-32, -32, -2))
	assert_vector3(hatch_size.size).is_equal(Vector3(32, 32, 2))

	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()
	assert_bool(text.find("size(-32 -32 -2, 32 32 2) = prop_door_floor_hatch") >= 0).is_true()

func test_custom_trenchbroom_point_class_bounds_use_grid_units():
	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var lines := file.get_as_text().split("\n")
	file.close()

	for raw_line in lines:
		var line := String(raw_line)
		var is_custom_point: bool = line.begins_with("@PointClass") and (line.find(" = prop_") >= 0 or line.find(" = light_") >= 0)
		if not is_custom_point or line.find("size(") < 0:
			continue
		var size_start := line.find("size(")
		var size_end := line.find(")", size_start)
		assert_bool(size_end > size_start).is_true()
		var size_text := line.substr(size_start, size_end - size_start + 1)
		assert_bool(size_text.find(".") == -1).is_true()

func test_forward_interact_proxy_respects_disabled_parent_interaction():
	var packed: PackedScene = load("res://core_v2/props/scifi_lights/SciFiWorkLightTripodV2.tscn")
	assert_object(packed).is_not_null()

	var prop: Node = auto_free(packed.instance())
	add_child(prop)
	yield(get_tree(), "idle_frame")

	var proxy: Node = prop.get_node("InteractionBody")
	assert_object(proxy).is_not_null()

	prop.set("is_interactable", false)
	if proxy.has_method("set_is_interactable"):
		proxy.set_is_interactable(false)

	assert_bool(prop.is_in_group("interactable")).is_false()
	assert_bool(proxy.is_in_group("interactable")).is_false()

func test_work_light_interaction_collision_does_not_extend_below_origin():
	var scene_paths := [
		"res://core_v2/props/scifi_lights/SciFiWorkLightV2.tscn",
		"res://core_v2/props/scifi_lights/SciFiWorkLightTripodV2.tscn",
	]

	for scene_path in scene_paths:
		var packed: PackedScene = load(String(scene_path))
		assert_object(packed).is_not_null()

		var prop: Spatial = auto_free(packed.instance())
		add_child(prop)
		yield(get_tree(), "idle_frame")

		var body: Spatial = prop.get_node("InteractionBody")
		var collision_shape: CollisionShape = body.get_node("CollisionShape")
		assert_object(body).is_not_null()
		assert_object(collision_shape).is_not_null()
		assert_object(collision_shape.shape).is_not_null()
		assert_bool(collision_shape.shape is BoxShape).is_true()

		var shape := collision_shape.shape as BoxShape
		var bottom_y: float = body.translation.y + collision_shape.translation.y - shape.extents.y
		assert_float(bottom_y).is_equal_approx(0.0, 0.001)

func test_work_light_tripod_feet_are_floor_aligned():
	var packed: PackedScene = load("res://core_v2/props/scifi_lights/SciFiWorkLightTripodV2.tscn")
	assert_object(packed).is_not_null()

	var prop: Spatial = auto_free(packed.instance())
	add_child(prop)
	yield(get_tree(), "idle_frame")

	var min_y := INF
	for path in [
		"Tripod/Leg1Pivot/Leg/Foot",
		"Tripod/Leg2Pivot/Leg/Foot",
		"Tripod/Leg3Pivot/Leg/Foot",
	]:
		var foot: CSGBox = prop.get_node(path)
		assert_object(foot).is_not_null()
		min_y = min(min_y, _box_min_y(foot, foot.width, foot.height, foot.depth))

	assert_float(min_y).is_equal_approx(0.0, 0.001)

func test_emergency_beacon_origin_is_mounting_back_face():
	var point_class: Resource = load("res://core_v2/qodot_fgd/props/EmergencyBeaconV2_point_class.tres")
	assert_object(point_class).is_not_null()
	var tb_size: AABB = point_class.get("meta_properties")["size"]
	assert_vector3(tb_size.position).is_equal(Vector3(-4, 0, -4))
	assert_vector3(tb_size.size).is_equal(Vector3(4, 8, 4))

	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()
	assert_bool(text.find("size(-4 0 -4, 4 8 4) = light_emergency_beacon") >= 0).is_true()

	var packed: PackedScene = load("res://core_v2/props/EmergencyBeaconV2.tscn")
	assert_object(packed).is_not_null()

	var prop: Spatial = auto_free(packed.instance())
	add_child(prop)
	yield(get_tree(), "idle_frame")

	var bounds := _mesh_instance_bounds(prop)
	assert_float(bounds.position.y).is_equal_approx(0.0, 0.001)
	assert_float(abs(bounds.position.z + bounds.size.z * 0.5)).is_less(0.03)

	var collision_shape: CollisionShape = prop.get_node("CollisionShape")
	assert_object(collision_shape).is_not_null()
	assert_bool(collision_shape.shape is CylinderShape).is_true()
	var cylinder := collision_shape.shape as CylinderShape
	var collision_back_y: float = collision_shape.translation.y - (cylinder.height * 0.5)
	var collision_center_z: float = collision_shape.translation.z
	assert_float(collision_back_y).is_greater_equal(-0.001)
	assert_float(collision_center_z).is_equal_approx(0.0, 0.001)

	var sfx: AudioStreamPlayer3D = prop.get_node("SFX Alarm")
	assert_object(sfx).is_not_null()
	assert_vector3(sfx.translation).is_equal(Vector3.ZERO)
	assert_int(_count_collision_shapes(sfx)).is_equal(0)
	assert_int(_count_collision_shapes(prop)).is_equal(1)

func test_baseterrace_work_light_matches_trenchbroom_overrides():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = auto_free(packed.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	var tripod: Node = scene.get_node_or_null("Terrace/Building/QodotMap/entity_4_light_work_tripod")
	assert_object(tripod).is_not_null()
	assert_float((tripod as Spatial).translation.y).is_equal_approx(0.0, 0.001)
	assert_float((tripod as Spatial).rotation_degrees.y).is_equal_approx(90.0, 0.001)
	assert_bool(tripod.get("is_interactable")).is_false()
	assert_bool(tripod.is_in_group("interactable")).is_false()

	var proxy: Node = tripod.get_node("InteractionBody")
	assert_object(proxy).is_not_null()
	assert_bool(proxy.is_in_group("interactable")).is_false()

	var spot: SpotLight = tripod.get_node("Head/SpotLight")
	assert_object(spot).is_not_null()
	assert_bool(spot.shadow_enabled).is_true()

func test_baseterrace_holo_terminal_keeps_single_viewport_input_tree():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = packed.instance()
	var terminal: Node = scene.get_node_or_null("Terrace/Building/TableTerminal")
	assert_object(terminal).is_not_null()
	assert_int(_count_direct_children_named(terminal, "Viewport")).is_equal(1)
	assert_int(_count_direct_children_named(terminal, "ScreenContainer")).is_equal(1)
	assert_int(_count_direct_children_named(terminal, "CinematicSetup")).is_equal(1)

	var viewport: Viewport = terminal.get_node_or_null("Viewport")
	assert_object(viewport).is_not_null()
	assert_object(viewport.get_script()).is_not_null()
	assert_str(viewport.get_script().resource_path).is_equal("res://core_v2/things/HoloTerminalViewportInput.gd")
	assert_object(viewport.get_node_or_null("TerminalUI")).is_not_null()
	assert_int(_count_descendants_named(terminal, "VirtualCursorLayer")).is_equal(0)

	scene.free()

func test_baseterrace_vcamera_system_keeps_single_camera_tree():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = packed.instance()
	var vcam_system: Node = scene.get_node_or_null("Terrace/Building/VCameraSystem")
	assert_object(vcam_system).is_not_null()
	assert_int(_count_direct_children_named(vcam_system, "VCameraBrain")).is_equal(1)
	assert_int(_count_direct_children_named(vcam_system, "VCameras")).is_equal(1)

	var vcameras: Node = vcam_system.get_node_or_null("VCameras")
	assert_object(vcameras).is_not_null()
	assert_int(_count_direct_children_named(vcameras, "IntroFar")).is_equal(1)
	assert_int(_count_direct_children_named(vcameras, "IntroClose")).is_equal(1)
	assert_int(_count_direct_children_named(vcameras, "IntroFinal")).is_equal(1)
	var intro_far_translation := (vcameras.get_node("IntroFar") as Spatial).translation
	assert_float(intro_far_translation.distance_to(Vector3(-7.43753, 3.65513, 7.16017))).is_less(0.001)
	assert_float(vcameras.get_node("IntroFar").get("fov")).is_equal_approx(60.0, 0.001)

	scene.free()

func test_baseterrace_start_criopod_keeps_single_player_audio_listener():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = packed.instance()
	var criopod: Node = scene.get_node_or_null("Terrace/Building/CrioPod START")
	assert_object(criopod).is_not_null()
	assert_int(_count_direct_children_named(criopod, "Pilot")).is_equal(1)
	assert_int(_count_direct_children_named(criopod, "RotatingObjectV2")).is_equal(1)
	assert_int(_count_direct_children_named(criopod, "Smoke")).is_equal(1)
	assert_int(_count_direct_children_named(criopod, "Sparks")).is_equal(1)

	var pilot: Node = criopod.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()
	assert_int(_count_direct_children_named(pilot, "AudioListener")).is_equal(1)
	assert_int(_count_descendants_of_class(criopod, "Listener")).is_equal(1)

	scene.free()

func test_baseterrace_emergency_beacons_are_wall_aligned():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = auto_free(packed.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var space := (scene as Spatial).get_world().direct_space_state
	for name in [
		"entity_6_light_emergency_beacon",
	]:
		var beacon: Spatial = scene.find_node(name, true, false)
		assert_object(beacon).is_not_null()
		var back := -beacon.global_transform.basis.y.normalized()
		var front := -back
		var from := beacon.global_transform.origin + front * 0.12
		var to := beacon.global_transform.origin + back * 0.25
		var hit := space.intersect_ray(from, to, [beacon], 2147483647, true, true)
		if hit.empty():
			continue
		var signed_hit: float = (hit.position - beacon.global_transform.origin).dot(back)
		assert_float(abs(signed_hit)).is_less(0.065)

func test_crio_map_emergency_beacon_z_axis_origin_is_wall_aligned():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://maps/crio.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.use_trenchbroom_group_hierarchy = true
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var beacon: Spatial = qodot_map.find_node("*_light_emergency_beacon", true, false)
	assert_object(beacon).is_not_null()
	var back := -beacon.global_transform.basis.y.normalized()
	var front := -back
	var space := qodot_map.get_world().direct_space_state
	var hit := space.intersect_ray(
		beacon.global_transform.origin + front * 0.12,
		beacon.global_transform.origin + back * 0.25,
		[beacon],
		2147483647,
		true,
		true
	)
	if not hit.empty():
		var signed_hit: float = (hit.position - beacon.global_transform.origin).dot(back)
		assert_float(abs(signed_hit)).is_less(0.065)

func test_qodot_map_restores_point_entities_skipped_by_native_parser():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://maps/crio.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.use_trenchbroom_group_hierarchy = true
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()

	var classnames := []
	for entity_dict in qodot_map.entity_dicts:
		var properties: Dictionary = entity_dict.get("properties", {})
		classnames.append(String(properties.get("classname", "")))

	assert_bool(classnames.has("prop_door_floor_hatch")).is_true()

	var hatch: Node = null
	for child in qodot_map.get_children():
		if child == null:
			continue
		if String(child.name).find("_prop_door_floor_hatch") != -1:
			hatch = child
			break
	assert_object(hatch).is_not_null()
	qodot_map.free()

func test_crio_map_builds_worldspawn_walls():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://maps/crio.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.use_trenchbroom_group_hierarchy = true
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()
	yield(get_tree(), "idle_frame")

	assert_bool(qodot_map.entity_mesh_dict.has(0)).is_true()
	var worldspawn: Node = qodot_map.get_node_or_null("entity_0_worldspawn")
	assert_object(worldspawn).is_not_null()
	assert_int(worldspawn.get_child_count()).is_greater(0)
	qodot_map.free()

func test_qodot_hides_ceiling_trenchbroom_layer_only_in_editor():
	var qodot_map_script: Script = load("res://addons/qodot/src/nodes/qodot_map.gd")
	assert_object(qodot_map_script).is_not_null()

	var qodot_map: Spatial = auto_free(Spatial.new())
	qodot_map.set_script(qodot_map_script)
	add_child(qodot_map)

	qodot_map.map_file = "res://maps/crio.map"
	qodot_map.inverse_scale_factor = 16.0
	qodot_map.entity_fgd = load("res://addons/qodot/game_definitions/fgd/qodot_fgd.tres")
	qodot_map.base_texture_dir = "res://textures"
	qodot_map.use_trenchbroom_group_hierarchy = true
	qodot_map.should_add_children = true
	qodot_map.should_set_owners = false
	qodot_map.block_until_complete = true
	qodot_map.verify_and_build()
	yield(get_tree(), "idle_frame")

	var ceiling_layer: Spatial = null
	for child in qodot_map.get_children():
		if not child is Spatial:
			continue
		if child.has_meta("trenchbroom_layer_name") and String(child.get_meta("trenchbroom_layer_name")) == "Ceiling":
			ceiling_layer = child
			break

	assert_object(ceiling_layer).is_not_null()
	assert_str(ceiling_layer.name).contains("Ceiling")
	assert_bool(ceiling_layer.has_meta("editor_hidden_trenchbroom_layer")).is_true()
	assert_bool(ceiling_layer.visible).is_true()
	assert_object(ceiling_layer.get_script()).is_not_null()
	assert_str(ceiling_layer.get_script().resource_path).is_equal("res://core_v2/levels/EditorHiddenLayer.gd")
	qodot_map.free()

func _collect_custom_point_class_blocks(text: String) -> Dictionary:
	var blocks := {}
	var offset := 0
	while true:
		var start := text.find("@PointClass", offset)
		if start < 0:
			break
		var body_start := text.find("[", start)
		var body_end := text.find("\n]", body_start)
		if body_start < 0 or body_end < 0:
			break
		var header := text.substr(start, body_start - start)
		var classname := _extract_custom_classname(header)
		if classname != "":
			blocks[classname] = text.substr(body_start + 1, body_end - body_start - 1)
		offset = body_end + 2
	return blocks

func _extract_custom_classname(header: String) -> String:
	var eq_pos := header.find("=")
	var colon_pos := header.find(":")
	if eq_pos < 0 or colon_pos < 0 or colon_pos <= eq_pos:
		return ""
	var classname := header.substr(eq_pos + 1, colon_pos - eq_pos - 1).strip_edges()
	if classname.begins_with("prop_") or classname.begins_with("light_"):
		return classname
	return ""

func _extract_point_class_block(text: String, target_classname: String) -> String:
	var blocks := _collect_custom_point_class_blocks(text)
	return String(blocks.get(target_classname, ""))

func _box_min_y(node: Spatial, width: float, height: float, depth: float) -> float:
	var extents := Vector3(width, height, depth) * 0.5
	var min_y := INF
	for x in [-extents.x, extents.x]:
		for y in [-extents.y, extents.y]:
			for z in [-extents.z, extents.z]:
				var point: Vector3 = node.global_transform.xform(Vector3(x, y, z))
				min_y = min(min_y, point.y)
	return min_y

func _count_direct_children_named(root: Node, child_name: String) -> int:
	var total := 0
	for child in root.get_children():
		if String(child.name) == child_name:
			total += 1
	return total

func _count_descendants_named(root: Node, node_name: String) -> int:
	var total := 0
	var stack := [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node != root and String(node.name) == node_name:
			total += 1
		for child in node.get_children():
			stack.append(child)
	return total

func _count_descendants_of_class(root: Node, target_class_name: String) -> int:
	var total := 0
	var stack := [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node != root and node.get_class() == target_class_name:
			total += 1
		for child in node.get_children():
			stack.append(child)
	return total

func _mesh_instance_bounds(root: Node) -> AABB:
	var found := false
	var bounds := AABB()
	var stack := [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance:
			var visual := node as MeshInstance
			var visual_bounds := _transform_aabb(visual.global_transform, visual.get_aabb())
			if found:
				bounds = bounds.merge(visual_bounds)
			else:
				bounds = visual_bounds
				found = true
		for child in node.get_children():
			stack.append(child)
	return bounds

func _count_collision_shapes(root: Node) -> int:
	var total := 0
	var stack := [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		if node is CollisionShape:
			total += 1
		for child in node.get_children():
			stack.append(child)
	return total

func _transform_aabb(xform: Transform, aabb: AABB) -> AABB:
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	for x in [aabb.position.x, aabb.position.x + aabb.size.x]:
		for y in [aabb.position.y, aabb.position.y + aabb.size.y]:
			for z in [aabb.position.z, aabb.position.z + aabb.size.z]:
				var point: Vector3 = xform.xform(Vector3(x, y, z))
				min_point.x = min(min_point.x, point.x)
				min_point.y = min(min_point.y, point.y)
				min_point.z = min(min_point.z, point.z)
				max_point.x = max(max_point.x, point.x)
				max_point.y = max(max_point.y, point.y)
				max_point.z = max(max_point.z, point.z)
	return AABB(min_point, max_point - min_point)
