extends SceneTree

# verify_pipe_network_bake.gd — sanity check for tools/bake_pipe_network.gd's output:
# loads DomeIntro_PipeNetworkSource.tscn (source) and Dome_Intro.tscn (product), and
# confirms each baked group's vertex count and collision-shape count match the source.
#
# Run: godot3-bin --no-window -s tools/verify_pipe_network_bake.gd

const SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
const DOME_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const GROUPS := ["CryoLoopWest", "CryoLoopEast", "TowerCoolantRiser"]

var _ok := true

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: Node = (load(SOURCE_PATH) as PackedScene).instance()
	var dome: Node = (load(DOME_PATH) as PackedScene).instance()
	get_root().add_child(source)
	get_root().add_child(dome)

	for _i in range(4):
		yield(self, "idle_frame")

	for group_name in GROUPS:
		_verify_group(source, dome, group_name)

	if _ok:
		print("[verify_pipes] OK: all groups match")
		quit(0)
	else:
		printerr("[verify_pipes] FAIL: mismatch found")
		quit(1)

func _verify_group(source: Node, dome: Node, group_name: String) -> void:
	var source_pipes: Spatial = source.get_node_or_null(group_name + "/Pipes")
	var dome_pipes: Spatial = dome.get_node_or_null(group_name + "/Pipes")
	if source_pipes == null or dome_pipes == null:
		printerr("[verify_pipes] %s: node missing (source=%s dome=%s)" % [group_name, source_pipes, dome_pipes])
		_ok = false
		return

	# Triangle count, not raw vertex count: the baked mesh is left non-indexed by
	# SurfaceTool.commit() (same as tools/bake_scaffold_walkways.gd), which duplicates
	# vertices per triangle corner, while the source PrimitiveMeshes are indexed. Triangle
	# count is invariant to that and is what actually proves no geometry was lost/added.
	var source_verts := 0
	var source_meshes := []
	_collect_mesh_instances(source_pipes, source_meshes)
	for mi in source_meshes:
		for s in range(mi.mesh.get_surface_count()):
			source_verts += _triangle_count(mi.mesh.surface_get_arrays(s))

	var dome_verts := 0
	var dome_meshes := []
	_collect_mesh_instances(dome_pipes, dome_meshes)
	for mi in dome_meshes:
		for s in range(mi.mesh.get_surface_count()):
			dome_verts += _triangle_count(mi.mesh.surface_get_arrays(s))

	var source_shapes := []
	_collect_collision_shapes(source_pipes, source_shapes)
	var dome_shapes := []
	_collect_collision_shapes(dome_pipes, dome_shapes)

	var verts_match: bool = source_verts == dome_verts
	var shapes_match: bool = source_shapes.size() == dome_shapes.size()
	print("[verify_pipes] %s: source_tris=%d dome_tris=%d source_shapes=%d dome_shapes=%d draw_calls_before=%d draw_calls_after=1" % [
		group_name, source_verts, dome_verts, source_shapes.size(), dome_shapes.size(), source_meshes.size()])
	if not verts_match or not shapes_match:
		_ok = false

func _triangle_count(arrays: Array) -> int:
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices is PoolIntArray and (indices as PoolIntArray).size() > 0:
		return (indices as PoolIntArray).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PoolVector3Array).size() / 3

func _collect_mesh_instances(node: Node, out_list: Array) -> void:
	if node is MeshInstance:
		out_list.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out_list)

func _collect_collision_shapes(node: Node, out_list: Array) -> void:
	if node is CollisionShape:
		out_list.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, out_list)
