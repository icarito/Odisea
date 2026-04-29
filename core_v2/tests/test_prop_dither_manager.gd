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
