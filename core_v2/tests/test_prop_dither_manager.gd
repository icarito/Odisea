extends GdUnitTestSuite

const PropDitherManagerScript := preload("res://core_v2/autoloads/PropDitherManager.gd")
const RoadLinesSeamMaterial := preload("res://materials/diamondPlateAluminum/seam_road_lines_pbr.tres")
const HubSpokesBody := preload("res://core_v2/levels/interiors/DomeIntro_HubSpokes_body.tscn")


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

	assert_bool(manager._has_albedo_map(source)).is_false()


func test_textured_material_enables_albedo_sampling() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())
	var source := SpatialMaterial.new()
	source.albedo_texture = ImageTexture.new()

	assert_bool(manager._has_albedo_map(source)).is_true()


func test_road_lines_seam_shader_supports_prop_occlusion() -> void:
	var manager: Node = auto_free(PropDitherManagerScript.new())

	assert_bool(manager._is_occlusion_shader(RoadLinesSeamMaterial.shader)).is_true()


func test_baked_hub_spokes_body_exposes_its_footstep_profile() -> void:
	var body: StaticBody = auto_free(HubSpokesBody.instance())

	assert_bool(body.has_meta("footstep_profile")).is_true()
	assert_object(body.get_meta("footstep_profile")).is_not_null()
