extends GdUnitTestSuite

const PropDitherManagerScript := preload("res://core_v2/autoloads/PropDitherManager.gd")


func test_collision_object_with_own_mesh_is_occlusion_root() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var body: StaticBody = auto_free(StaticBody.new())
	var mesh := MeshInstance.new()
	mesh.mesh = CubeMesh.new()
	body.add_child(mesh)

	assert_object(manager._get_occlusion_root_for_collision_object(body)).is_same(body)


func test_helper_collision_without_mesh_uses_parent_prop_root() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var prop_root: Spatial = auto_free(Spatial.new())
	var body := StaticBody.new()
	prop_root.add_child(body)

	assert_object(manager._get_occlusion_root_for_collision_object(body)).is_same(prop_root)


func test_collision_object_with_multimesh_descendant_is_occlusion_root() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var body: StaticBody = auto_free(StaticBody.new())
	var inst := MultiMeshInstance.new()
	inst.multimesh = MultiMesh.new()
	body.add_child(inst)

	assert_object(manager._get_occlusion_root_for_collision_object(body)).is_same(body)


func test_untextured_material_does_not_sample_an_empty_mobile_texture() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var source := SpatialMaterial.new()
	var converted: ShaderMaterial = manager._convert_spatial_to_dither(source)

	assert_bool(converted.get_shader_param("has_albedo_map")).is_false()


func test_textured_material_enables_albedo_sampling() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var source := SpatialMaterial.new()
	source.albedo_texture = ImageTexture.new()
	var converted: ShaderMaterial = manager._convert_spatial_to_dither(source)

	assert_bool(converted.get_shader_param("has_albedo_map")).is_true()
