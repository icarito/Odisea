extends SceneTree

# One-off: restore the wall lamp's glass shade as a second, OPAQUE emissive
# surface on the source mesh (the transparent glass surface from the glTF
# import was dropped when IndustrialWallLampLow.mesh was first authored).
# Rebuild with:
#   godot3-bin --no-window --audio-driver Dummy --path . \
#     -s res://tools/add_wall_lamp_glass_surface.gd
# Then rerun build_wall_lamp_lod.gd and bake_dome_wall_sconces.gd.

const GLTF_PATH := "res://assets/models/Industrial Wall Lamp/1k/industrial_wall_lamp_1k.gltf"
const LOW_MESH_PATH := "res://core_v2/props/scifi_lights/IndustrialWallLampLow.mesh"
const GLASS_SURFACE_INDEX := 1

func _init() -> void:
	var packed: PackedScene = load(GLTF_PATH) as PackedScene
	if packed == null:
		_fail("Could not load source glTF")
		return
	var root: Node = packed.instance()
	var glass_mi: MeshInstance = _find_mesh_instance(root)
	if glass_mi == null or glass_mi.mesh.get_surface_count() <= GLASS_SURFACE_INDEX:
		root.free()
		_fail("Source mesh has no glass surface")
		return
	var glass_arrays: Array = glass_mi.mesh.surface_get_arrays(GLASS_SURFACE_INDEX)
	root.free()

	var low: ArrayMesh = load(LOW_MESH_PATH) as ArrayMesh
	if low == null or low.get_surface_count() < 1:
		_fail("Unexpected IndustrialWallLampLow.mesh surface count")
		return

	var glass_material := SpatialMaterial.new()
	glass_material.flags_transparent = false
	glass_material.flags_unshaded = true
	glass_material.albedo_color = Color(0.72, 0.84, 1, 1)
	glass_material.emission_enabled = true
	glass_material.emission = Color(0.72, 0.84, 1, 1)
	glass_material.emission_energy = 0.6
	glass_material.resource_name = "industrial_wall_lamp_glass_opaque"

	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, low.surface_get_arrays(0))
	out.surface_set_material(0, low.surface_get_material(0))
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass_arrays)
	out.surface_set_material(1, glass_material)
	out.resource_name = "IndustrialWallLampLow"

	var result: int = ResourceSaver.save(LOW_MESH_PATH, out)
	if result != OK:
		_fail("ResourceSaver failed with code %d" % result)
		return
	print("Added opaque emissive glass surface to %s" % LOW_MESH_PATH)
	quit()

func _find_mesh_instance(node: Node) -> MeshInstance:
	if node is MeshInstance and (node as MeshInstance).mesh != null:
		return node as MeshInstance
	for child in node.get_children():
		var found: MeshInstance = _find_mesh_instance(child)
		if found != null:
			return found
	return null

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
