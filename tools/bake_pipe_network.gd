extends SceneTree

# bake_pipe_network.gd — Merges each coolant "Pipes" group (CryoLoopWest, CryoLoopEast,
# TowerCoolantRiser, TowerCoolantRiserEast, BridgeFloor5) in Dome_Intro into one combined
# MeshInstance plus one StaticBody sub-scene, same pattern as tools/bake_scaffold_walkways.gd.
#
# Each group is built from several PipeSection/PipeTee instances, each with its own
# MeshInstance + StaticBody/CollisionShape — one draw call and one collision object per
# section on a mobile GPU that already pays dearly for draw calls. All of them share one
# material (PipeMetal.tres) before PipeCoolantRun overrides it at runtime with a shared
# per-corrida flow ShaderMaterial, so this collapses each group's visual geometry into a
# SINGLE surface. PipeCoolantRun.gd needs no changes: it already recurses get_children()
# looking for MeshInstance and calls set_surface_material(0, ...); after baking there is
# just one child instead of several.
#
# CoolantValve (PipeValve.tscn) instances are interactive and are NOT part of the source
# subscene or this bake — they stay hand-placed and live in Dome_Intro.
#
# Run: godot3-bin --no-window -s tools/bake_pipe_network.gd
# Output: core_v2/levels/interiors/DomeIntro_<Group>Pipes_baked.mesh
#         core_v2/levels/interiors/DomeIntro_<Group>Pipes_body.tscn

const DEFAULT_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
const GROUPS := ["CryoLoopWest", "CryoLoopEast", "TowerCoolantRiser", "TowerCoolantRiserEast", "BridgeFloor5"]
const OUT_DIR := "res://core_v2/levels/interiors/"

var _texture_keys := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path: String = OS.get_environment("ODISEA_BAKE_SOURCE")
	if source_path.empty():
		source_path = DEFAULT_SOURCE_PATH
	var scene: PackedScene = load(source_path)
	if scene == null:
		push_error("Could not load source %s" % source_path)
		quit(1)
		return

	# Same guard as bake_scaffold_walkways.gd: PipeSection/PipeTee's StaticBody sits on
	# collision_layer 64 (Prop), so PropDitherManager (autoload) would otherwise convert
	# their MeshInstance's SpatialMaterial to a runtime dither ShaderMaterial while this
	# instances the source, and the bake would collect THAT instead of the authored
	# material.
	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")
		print("[bake_pipes] PropDitherManager desactivado para hornear")

	var root: Node = scene.instance()
	get_root().add_child(root)

	for _i in range(4):
		yield(self, "idle_frame")

	var selected_group: String = OS.get_environment("ODISEA_BAKE_GROUP")
	for group_name in GROUPS:
		if not selected_group.empty() and group_name != selected_group:
			continue
		_bake_group(root, group_name)

	quit(0)

func _bake_group(root: Node, group_name: String) -> void:
	var pipes: Spatial = root.get_node_or_null(group_name + "/Pipes")
	if pipes == null:
		push_error("[bake_pipes] group not found: %s/Pipes" % group_name)
		return

	if pipes.get_node_or_null("CombinedMesh") != null:
		print("[bake_pipes] %s: ya cableado (CombinedMesh presente), se omite" % group_name)
		return

	var mesh_instances := []
	_collect_mesh_instances(pipes, mesh_instances)
	print("[bake_pipes] %s: %d source MeshInstances" % [group_name, mesh_instances.size()])
	if mesh_instances.empty():
		push_error("[bake_pipes] %s produced no MeshInstances - is it built?" % group_name)
		return

	var group_xform_inv: Transform = pipes.global_transform.affine_inverse()
	var surface_tools := {}
	var signature_material := {}
	var signature_order := []

	for mi in mesh_instances:
		if mi.mesh == null:
			continue
		var mi_to_group: Transform = group_xform_inv * mi.global_transform
		for surf_idx in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_material(surf_idx)
			if mat == null:
				mat = mi.mesh.surface_get_material(surf_idx)

			var uv_scale := Vector2(1.0, 1.0)
			var uv_offset := Vector2(0.0, 0.0)
			if mat is SpatialMaterial:
				var sm := mat as SpatialMaterial
				uv_scale = Vector2(sm.uv1_scale.x, sm.uv1_scale.y)
				uv_offset = Vector2(sm.uv1_offset.x, sm.uv1_offset.y)

			var sig := _material_signature(mat)
			if not surface_tools.has(sig):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface_tools[sig] = st
				signature_order.append(sig)
				signature_material[sig] = _neutralized_material(mat)
			_append_transformed_surface(surface_tools[sig], mi.mesh, surf_idx, mi_to_group,
				uv_scale, uv_offset)

	var combined := ArrayMesh.new()
	for i in range(signature_order.size()):
		var sig = signature_order[i]
		var st: SurfaceTool = surface_tools[sig]
		st.generate_normals()
		var mat: Material = signature_material[sig]
		if mat != null:
			mat = _save_shared_material(group_name, i, mat)
			st.set_material(mat)
		st.commit(combined)

	var collision_shapes := []
	var shape_nodes := []
	_collect_collision_shapes(pipes, shape_nodes)
	print("[bake_pipes] %s: %d source CollisionShapes" % [group_name, shape_nodes.size()])
	for cs in shape_nodes:
		if cs.shape == null:
			continue
		var cs_to_group: Transform = group_xform_inv * cs.global_transform
		collision_shapes.append([cs.shape, cs_to_group])

	var out_mesh_path := OUT_DIR + "DomeIntro_%sPipes_baked.mesh" % group_name
	if ResourceSaver.save(out_mesh_path, combined) != OK:
		push_error("[bake_pipes] failed to save %s" % out_mesh_path)
		return

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

	var body_packed := PackedScene.new()
	body_packed.pack(body)
	var out_body_path := OUT_DIR + "DomeIntro_%sPipes_body.tscn" % group_name
	if ResourceSaver.save(out_body_path, body_packed) != OK:
		push_error("[bake_pipes] failed to save %s" % out_body_path)
		return

	var vcount := 0
	for i in range(combined.get_surface_count()):
		vcount += (combined.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	print("[bake_pipes] %s: %d surfaces, %d verts, %d collision shapes -> %s / %s" % [
		group_name, combined.get_surface_count(), vcount, collision_shapes.size(), out_mesh_path, out_body_path])

func _save_shared_material(group_name: String, index: int, mat: Material) -> Material:
	var path: String = OUT_DIR + "DomeIntro_%sPipes_mat_%02d.material" % [group_name, index]
	if ResourceSaver.save(path, mat) != OK:
		push_error("[bake_pipes] failed to save %s" % path)
		return mat
	var loaded: Material = load(path)
	return loaded if loaded != null else mat

func _material_signature(mat: Material) -> String:
	if mat == null:
		return "<null>"
	var parts := PoolStringArray()
	parts.append(mat.get_class())
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		parts.append("shader=" + (sm.shader.resource_path if sm.shader else "-"))
		if sm.shader != null:
			for p in VisualServer.shader_get_param_list(sm.shader.get_rid()):
				parts.append("%s=%s" % [p.name, _value_key(sm.get_shader_param(p.name))])
		return parts.join("|")
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var pname: String = p.name
		if pname in ["resource_path", "resource_name", "resource_local_to_scene", "uv1_scale", "uv1_offset"]:
			continue
		parts.append("%s=%s" % [pname, _value_key(mat.get(pname))])
	return parts.join("|")

func _value_key(v) -> String:
	if v is Texture:
		return "tex:" + _texture_key(v as Texture)
	if v is Resource:
		var r := v as Resource
		return "res:" + r.resource_path if r.resource_path != "" else "obj:%d" % r.get_instance_id()
	return str(v)

func _texture_key(t: Texture) -> String:
	var id: int = t.get_instance_id()
	if _texture_keys.has(id):
		return _texture_keys[id]
	var key := "obj:%d" % id
	if t.resource_path != "" and not ("::" in t.resource_path):
		key = t.resource_path
	else:
		var img: Image = t.get_data()
		if img != null:
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_MD5)
			ctx.update(img.get_data())
			key = "img:%dx%d:%s" % [img.get_width(), img.get_height(), ctx.finish().hex_encode()]
	_texture_keys[id] = key
	return key

func _neutralized_material(mat: Material) -> Material:
	if not (mat is SpatialMaterial):
		return mat
	var sm := mat as SpatialMaterial
	if sm.uv1_scale == Vector3(1, 1, 1) and sm.uv1_offset == Vector3.ZERO:
		return mat
	var copy := sm.duplicate() as SpatialMaterial
	copy.uv1_scale = Vector3(1, 1, 1)
	copy.uv1_offset = Vector3.ZERO
	return copy

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

func _append_transformed_surface(st: SurfaceTool, mesh: Mesh, surf_idx: int, xform: Transform,
		uv_scale: Vector2 = Vector2(1, 1), uv_offset: Vector2 = Vector2(0, 0)) -> void:
	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var tangents = arrays[Mesh.ARRAY_TANGENT]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()

	if indices != null and (indices as PoolIntArray).size() > 0:
		for idx in (indices as PoolIntArray):
			_add_vertex(st, verts[idx], normals[idx] if normals != null else null,
				uvs[idx] if uvs != null else null, tangents, idx, xform, normal_basis, uv_scale, uv_offset)
	else:
		for i in range(verts.size()):
			_add_vertex(st, verts[i], normals[i] if normals != null else null,
				uvs[i] if uvs != null else null, tangents, i, xform, normal_basis, uv_scale, uv_offset)

func _add_vertex(st: SurfaceTool, v: Vector3, n, uv, tangents, source_index: int, xform: Transform, normal_basis: Basis,
		uv_scale: Vector2 = Vector2(1, 1), uv_offset: Vector2 = Vector2(0, 0)) -> void:
	if uv != null:
		st.add_uv(Vector2(uv.x * uv_scale.x + uv_offset.x, uv.y * uv_scale.y + uv_offset.y))
	if n != null:
		st.add_normal(normal_basis.xform(n).normalized())
	if tangents != null and tangents.size() >= (source_index + 1) * 4:
		var tangent_offset: int = source_index * 4
		var tangent: Vector3 = xform.basis.xform(Vector3(
			tangents[tangent_offset], tangents[tangent_offset + 1], tangents[tangent_offset + 2]
		)).normalized()
		var handedness: float = tangents[tangent_offset + 3]
		if xform.basis.determinant() < 0.0:
			handedness *= -1.0
		st.add_tangent(Plane(tangent, handedness))
	st.add_vertex(xform.xform(v))
