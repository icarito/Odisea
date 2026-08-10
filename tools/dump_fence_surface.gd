extends SceneTree

# dump_fence_surface.gd — Compara los paneles de reja (metal_fence_panel) tal como
# los genera SteelGratePlatform en vivo contra los que quedaron en la malla
# horneada: cantidad de quads, rango de UV y esquinas en espacio del grupo.

const SOURCE_SCENE := "res://core_v2/levels/interiors/DomeIntro_ScaffoldSource.tscn"
const BAKED := "res://core_v2/levels/interiors/DomeIntro_SpiralStairs_baked.mesh"
const GROUP := "SpiralStairs"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(SOURCE_SCENE)
	var root: Node = packed.instance()
	get_root().add_child(root)
	for _i in range(30):
		yield(self, "idle_frame")

	var group: Spatial = root.get_node(GROUP)
	var inv: Transform = group.global_transform.affine_inverse()
	var panels := []
	_collect_panels(group, panels)
	print("LIVE: %d paneles de reja" % panels.size())
	for i in range(min(2, panels.size())):
		var mi: MeshInstance = panels[i]
		var mat = mi.material_override
		var scale_text := "-"
		if mat is SpatialMaterial:
			scale_text = str((mat as SpatialMaterial).uv1_scale)
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var xform: Transform = inv * mi.global_transform
		print("  panel %s mat=%s uv1_scale=%s size=%s" % [
			mi.name, mat.get_class(), scale_text,
			str(mi.mesh.size) if mi.mesh is QuadMesh else "?"])
		for v in range(verts.size()):
			print("    v%d pos=%s uv=%s uv*scale=%s" % [
				v, str(xform.xform(verts[v])), str(uvs[v]),
				str(uvs[v] * (mat as SpatialMaterial).uv1_scale.x)])

	var mesh: ArrayMesh = load(BAKED)
	for s in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(s)
		if not (mat is SpatialMaterial):
			continue
		var sp := mat as SpatialMaterial
		if sp.albedo_texture == null or not ("fence" in sp.albedo_texture.resource_path):
			continue
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		print("BAKED surf %d: %d verts, uv1_scale=%s" % [s, verts.size(), str(sp.uv1_scale)])
		var umin := Vector2(99999, 99999)
		var umax := Vector2(-99999, -99999)
		for uv in uvs:
			umin.x = min(umin.x, uv.x)
			umin.y = min(umin.y, uv.y)
			umax.x = max(umax.x, uv.x)
			umax.y = max(umax.y, uv.y)
		print("  uv range %s .. %s" % [str(umin), str(umax)])
		for v in range(min(12, verts.size())):
			print("    v%d pos=%s uv=%s" % [v, str(verts[v]), str(uvs[v])])
	quit(0)

func _collect_panels(node: Node, out_list: Array) -> void:
	if node is MeshInstance and node.mesh is QuadMesh:
		out_list.append(node)
	for child in node.get_children():
		_collect_panels(child, out_list)
