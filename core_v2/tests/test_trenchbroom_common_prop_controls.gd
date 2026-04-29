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

func test_baseterrace_work_light_matches_trenchbroom_overrides():
	var packed: PackedScene = load("res://core_v2/levels/BaseTerrace.tscn")
	assert_object(packed).is_not_null()

	var scene: Node = auto_free(packed.instance())
	add_child(scene)
	yield(get_tree(), "idle_frame")

	var tripod: Node = scene.get_node("Building/QodotMap/entity_9_light_work_tripod")
	assert_object(tripod).is_not_null()
	assert_bool(tripod.get("is_interactable")).is_false()
	assert_bool(tripod.is_in_group("interactable")).is_false()

	var proxy: Node = tripod.get_node("InteractionBody")
	assert_object(proxy).is_not_null()
	assert_bool(proxy.is_in_group("interactable")).is_false()

	var spot: SpotLight = tripod.get_node("Head/SpotLight")
	assert_object(spot).is_not_null()
	assert_bool(spot.shadow_enabled).is_true()

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
