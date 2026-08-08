extends SceneTree

# bake_scaffold_walkways.gd — Merges the SpiralStairs, HubSpokes and SpiralWalkways
# groups in Dome_Intro into one combined MeshInstance plus one StaticBody
# sub-scene (all original CollisionShapes reparented under it) each.
#
# Each group is built from several SteelGratePlatform instances (via RadialScatter
# for SpiralStairs/SpiralWalkways, or placed by hand for HubSpokes). Every leg,
# rail post and joint on a SteelGratePlatform is its own MeshInstance (see
# SteelGratePlatform.gd _add_tube_between/_add_joint_cap) — dozens of separate
# VisualServer draw items per platform, which is the CPU cost this scene's live
# hotzone recorder is catching at the top of the tower (confirmed live: dc/obj
# counters at that spot dropped by more than half after baking). This bakes the
# VISUAL geometry into one combined mesh per group, same pattern ScaffoldHubRing
# already uses for the ring floors.
#
# Collision is NOT derived from that combined visual mesh (a trimesh over every
# rail tube/joint produced a messy concave collider that narrowed the walkable
# path). Instead each platform's own clean CollisionShape nodes (one
# ConvexPolygonShape per deck, a few CylinderShapes per leg) are reparented as-is
# under one new StaticBody, saved as its own small sub-scene.
#
# Run: godot3-bin --no-window -s tools/bake_scaffold_walkways.gd
# Output: core_v2/levels/interiors/DomeIntro_<Group>_baked.mesh
#         core_v2/levels/interiors/DomeIntro_<Group>_body.tscn

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const GROUPS := ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
const OUT_DIR := "res://core_v2/levels/interiors/"
const FOOTSTEP_SURFACE_SCRIPT := "res://core_v2/systems/footsteps/footstep_surface.gd"
const FOOTSTEP_PROFILE_METAL := "res://core_v2/audio/footsteps/footstep_profile_scaffold_metal.tres"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return
	var root: Node = scene.instance()
	get_root().add_child(root)

	# RadialScatter.build() is call_deferred, and each SteelGratePlatform builds
	# itself in _ready via _rebuild() (also queued). Give it several idle frames
	# to fully settle before harvesting geometry.
	for _i in range(20):
		yield(self, "idle_frame")

	for group_name in GROUPS:
		_bake_group(root, group_name)

	quit(0)

func _bake_group(root: Node, group_name: String) -> void:
	var group: Spatial = root.get_node_or_null(group_name)
	if group == null:
		push_error("[bake_walkways] group not found: %s" % group_name)
		return

	var mesh_instances := []
	_collect_mesh_instances(group, mesh_instances)
	print("[bake_walkways] %s: %d source MeshInstances" % [group_name, mesh_instances.size()])
	if mesh_instances.empty():
		push_error("[bake_walkways] %s produced no MeshInstances - is it built?" % group_name)
		return

	var group_xform_inv: Transform = group.global_transform.affine_inverse()
	var surface_tools := {}      # material (or null) -> SurfaceTool
	var material_order := []     # preserves first-seen order for deterministic output

	for mi in mesh_instances:
		if mi.mesh == null:
			continue
		var mi_to_group: Transform = group_xform_inv * mi.global_transform
		for surf_idx in range(mi.mesh.get_surface_count()):
			# SteelGratePlatform assigns whole-node material_override (not
			# per-surface surface_material), so that has to be checked first —
			# get_surface_material() only sees per-surface overrides and would
			# otherwise return null for every tube/joint/deck here.
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_material(surf_idx)
			if mat == null:
				mat = mi.mesh.surface_get_material(surf_idx)
			if not surface_tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface_tools[mat] = st
				material_order.append(mat)
			_append_transformed_surface(surface_tools[mat], mi.mesh, surf_idx, mi_to_group)

	var combined := ArrayMesh.new()
	for mat in material_order:
		var st: SurfaceTool = surface_tools[mat]
		st.generate_normals()
		if mat != null:
			st.set_material(mat)
		st.commit(combined)

	# Collision: reuse each platform's own CollisionShape resources (a clean
	# ConvexPolygonShape per deck plus a few CylinderShapes per leg) instead of
	# deriving a trimesh from the full visual mesh. The visual mesh also
	# contains every rail tube and joint sphere; trimeshing that produces a
	# messy concave collider whose thin protrusions narrow the walkable area
	# right at the rail line - that's the "collision too narrow" regression.
	var collision_shapes := []  # Array of [Shape, Transform-in-group-space]
	var shape_nodes := []
	_collect_collision_shapes(group, shape_nodes)
	print("[bake_walkways] %s: %d source CollisionShapes" % [group_name, shape_nodes.size()])
	for cs in shape_nodes:
		if cs.shape == null:
			continue
		var cs_to_group: Transform = group_xform_inv * cs.global_transform
		collision_shapes.append([cs.shape, cs_to_group])

	var out_mesh_path := OUT_DIR + "DomeIntro_%s_baked.mesh" % group_name
	if ResourceSaver.save(out_mesh_path, combined) != OK:
		push_error("[bake_walkways] failed to save %s" % out_mesh_path)
		return

	# Pack the StaticBody + all its CollisionShapes (dozens of small convex/
	# cylinder shapes, one clean subtree) into its own sub-scene so Dome_Intro's
	# node text stays a single instanced child instead of dozens of hand-written
	# CollisionShape blocks.
	var body := StaticBody.new()
	body.name = "StaticBody"
	body.collision_layer = 64
	body.collision_mask = 255
	for i in range(collision_shapes.size()):
		var pair = collision_shapes[i]
		var cs := CollisionShape.new()
		cs.name = "Collision_%d" % i
		cs.shape = pair[0]
		cs.transform = pair[1]
		body.add_child(cs)
		cs.owner = body
	var footstep := Spatial.new()
	footstep.name = "FootstepSurface"
	footstep.set_script(load(FOOTSTEP_SURFACE_SCRIPT))
	footstep.set("footstep_profile", load(FOOTSTEP_PROFILE_METAL))
	body.add_child(footstep)
	footstep.owner = body

	var body_packed := PackedScene.new()
	body_packed.pack(body)
	var out_body_path := OUT_DIR + "DomeIntro_%s_body.tscn" % group_name
	if ResourceSaver.save(out_body_path, body_packed) != OK:
		push_error("[bake_walkways] failed to save %s" % out_body_path)
		return

	var vcount := 0
	for i in range(combined.get_surface_count()):
		vcount += (combined.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	print("[bake_walkways] %s: %d surfaces, %d verts, %d collision shapes -> %s / %s" % [
		group_name, combined.get_surface_count(), vcount, collision_shapes.size(), out_mesh_path, out_body_path])

func _collect_collision_shapes(node: Node, out_list: Array) -> void:
	if node is CollisionShape:
		out_list.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, out_list)

func _collect_mesh_instances(node: Node, out_list: Array) -> void:
	if node is MeshInstance:
		out_list.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out_list)

func _append_transformed_surface(st: SurfaceTool, mesh: Mesh, surf_idx: int, xform: Transform) -> void:
	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()

	if indices != null and (indices as PoolIntArray).size() > 0:
		for idx in (indices as PoolIntArray):
			_add_vertex(st, verts[idx], normals[idx] if normals != null else null,
				uvs[idx] if uvs != null else null, xform, normal_basis)
	else:
		for i in range(verts.size()):
			_add_vertex(st, verts[i], normals[i] if normals != null else null,
				uvs[i] if uvs != null else null, xform, normal_basis)

func _add_vertex(st: SurfaceTool, v: Vector3, n, uv, xform: Transform, normal_basis: Basis) -> void:
	if uv != null:
		st.add_uv(uv)
	if n != null:
		st.add_normal(normal_basis.xform(n).normalized())
	st.add_vertex(xform.xform(v))
