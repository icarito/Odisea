extends SceneTree

# verify_signage_bake.gd — sanity check for tools/bake_signage_panels.gd's output:
# confirms the baked mesh has one panel's worth of triangles per source SignagePanel
# (front + mirrored back for double_sided ones) and that collision-shape count matches.
#
# Run: godot3-bin --no-window -s tools/verify_signage_bake.gd

const SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_SignageSource.tscn"
const BAKED_MESH_PATH := "res://core_v2/levels/interiors/DomeIntro_SignagePanels_baked.mesh"
const BAKED_BODY_PATH := "res://core_v2/levels/interiors/DomeIntro_SignagePanels_body.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: Node = (load(SOURCE_PATH) as PackedScene).instance()
	get_root().add_child(source)

	var panels := []
	for child in source.get_children():
		if child.has_method("update_text"):
			panels.append(child)

	var expected_tris := 0
	var expected_shapes := 0
	for panel in panels:
		var mi: MeshInstance = panel.get_node_or_null("MeshInstance")
		var quad_tris: int = 0
		if mi != null and mi.mesh != null:
			var arrays: Array = mi.mesh.surface_get_arrays(0)
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices is PoolIntArray and (indices as PoolIntArray).size() > 0:
				quad_tris = (indices as PoolIntArray).size() / 3
			else:
				quad_tris = (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size() / 3
		var double_sided: bool = bool(panel.get("double_sided"))
		expected_tris += quad_tris * (2 if double_sided else 1)
		if panel.get_node_or_null("StaticBody/CollisionShape") != null:
			expected_shapes += 1

	var baked: ArrayMesh = load(BAKED_MESH_PATH)
	var baked_tris := 0
	for s in range(baked.get_surface_count()):
		var arrays: Array = baked.surface_get_arrays(s)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices is PoolIntArray and (indices as PoolIntArray).size() > 0:
			baked_tris += (indices as PoolIntArray).size() / 3
		else:
			baked_tris += (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size() / 3

	var body_packed: PackedScene = load(BAKED_BODY_PATH)
	var body: Node = body_packed.instance()
	var baked_shapes := 0
	for child in body.get_children():
		if child is CollisionShape:
			baked_shapes += 1

	print("[verify_signage] panels=%d expected_tris=%d baked_tris=%d expected_shapes=%d baked_shapes=%d" % [
		panels.size(), expected_tris, baked_tris, expected_shapes, baked_shapes])

	if expected_tris == baked_tris and expected_shapes == baked_shapes:
		print("[verify_signage] OK")
		quit(0)
	else:
		printerr("[verify_signage] FAIL: mismatch")
		quit(1)
