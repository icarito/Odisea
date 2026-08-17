extends SceneTree

# bake_signage_panels.gd — Bakes the 16 static SignagePanel instances in
# DomeIntro_SignageSource.tscn into ONE combined double-sided mesh + one shared texture
# atlas + one StaticBody, same "many small props -> one draw call" idea as
# tools/bake_scaffold_walkways.gd and tools/bake_pipe_network.gd.
#
# Unlike those, each SignagePanel isn't just static geometry: it spawns its own live
# sub-Viewport that renders its text to a texture ONCE (UPDATE_ONCE) and feeds that to a
# per-instance HoloGlass ShaderMaterial. That's 12 unbatchable draw calls (unique texture
# each) plus 12 live Viewport render targets sitting in VRAM, for text that never changes
# at runtime. This bake:
#   1. Lets every panel's Viewport render its text once (same timing the runtime panel
#      itself relies on - see SignagePanel.gd's update_text()).
#   2. Captures each rendered texture into one shared atlas image.
#   3. Rebuilds each panel's front-face QuadMesh geometry (just remapping its UV into the
#      atlas cell - the vertex positions/normals are untouched, so this can't drift from
#      what the panel already displays) plus a mirrored back face baked directly into the
#      geometry (double_sided=true on every current panel), replacing the runtime
#      HoloGlass shader flip with plain double geometry and one shared unshaded/emissive
#      SpatialMaterial.
#
# Run: godot3-bin --no-window -s tools/bake_signage_panels.gd
# Output: core_v2/levels/interiors/DomeIntro_SignageAtlas.tres (ImageTexture)
#         core_v2/levels/interiors/DomeIntro_SignagePanels_baked.mesh
#         core_v2/levels/interiors/DomeIntro_SignagePanels_body.tscn

const DEFAULT_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_SignageSource.tscn"
const OUT_DIR := "res://core_v2/levels/interiors/"
const ATLAS_COLS := 4
const ATLAS_ROWS := 4
const CELL_SIZE := Vector2(512, 308) # 1px slack below each 512x307 viewport capture
const PANEL_SIZE := Vector2(512, 307)

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

	var root: Node = scene.instance()
	get_root().add_child(root)

	var panels := []
	for child in root.get_children():
		if child.has_method("update_text"):
			panels.append(child)
	panels.sort_custom(self, "_sort_by_name")

	if panels.size() > ATLAS_COLS * ATLAS_ROWS:
		push_error("[bake_signage] %d panels don't fit a %dx%d atlas" % [panels.size(), ATLAS_COLS, ATLAS_ROWS])
		quit(1)
		return

	# Two single-shot Viewport renders happen back to back (see SignagePanel.gd
	# update_text()): the first draws the background before glyphs exist, the second
	# (re-armed via call_deferred) draws once the DynamicFont has rasterized them. Wait
	# generously past that before reading pixels back.
	for _i in range(60):
		yield(self, "idle_frame")

	var atlas_size := Vector2(CELL_SIZE.x * ATLAS_COLS, CELL_SIZE.y * ATLAS_ROWS)
	var atlas_img := Image.new()
	atlas_img.create(int(atlas_size.x), int(atlas_size.y), false, Image.FORMAT_RGBA8)
	atlas_img.lock()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(panels.size()):
		var panel: Spatial = panels[i]
		var viewport: Viewport = panel.get_node_or_null("_Viewport")
		if viewport == null:
			push_error("[bake_signage] %s has no _Viewport (update_text never ran?)" % panel.name)
			continue
		var panel_img: Image = viewport.get_texture().get_data()
		if panel_img.get_size() != PANEL_SIZE:
			push_error("[bake_signage] %s viewport size %s != expected %s" % [panel.name, panel_img.get_size(), PANEL_SIZE])
		panel_img.lock()
		var col: int = i % ATLAS_COLS
		var row: int = i / ATLAS_COLS
		var dst := Vector2(col * CELL_SIZE.x, row * CELL_SIZE.y)
		atlas_img.blit_rect(panel_img, Rect2(Vector2.ZERO, panel_img.get_size()), dst)
		panel_img.unlock()

		var u0: float = dst.x / atlas_size.x
		var v0: float = dst.y / atlas_size.y
		var u1: float = (dst.x + PANEL_SIZE.x) / atlas_size.x
		var v1: float = (dst.y + PANEL_SIZE.y) / atlas_size.y
		_append_panel(st, panel, u0, v0, u1, v1)
		print("[bake_signage] %s -> cell (%d,%d) uv[%.4f,%.4f - %.4f,%.4f]" % [panel.name, col, row, u0, v0, u1, v1])

	atlas_img.unlock()

	var atlas_tex := ImageTexture.new()
	atlas_tex.create_from_image(atlas_img, 0)
	var atlas_path := OUT_DIR + "DomeIntro_SignageAtlas.tres"
	if ResourceSaver.save(atlas_path, atlas_tex) != OK:
		push_error("[bake_signage] failed to save %s" % atlas_path)
		quit(1)
		return
	# Also drop a plain PNG next to it purely for visual inspection (not loaded at runtime).
	atlas_img.save_png(ProjectSettings.globalize_path(OUT_DIR + "DomeIntro_SignageAtlas_preview.png"))

	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	# Opaco a proposito: los 12 paneles de EnvironmentalSignage tienen panel_alpha=1.0 y
	# hologram_mode=false (ninguno pide transparencia real), asi que no hace falta pagar
	# el costo de la cola transparente. Un SpatialMaterial transparente participa del
	# render-order por distancia contra OTROS objetos transparentes de la escena (el
	# holoterminal, por ejemplo) usando el AABB del MeshInstance completo - y el
	# combinado de los 12 paneles abarca el domo entero (32x23x32m), asi que ese sort
	# ubicaba mal el mesh combinado contra props transparentes cercanos a un panel
	# individual. Opaco usa el z-buffer normal, que no le importa el orden de dibujado.
	mat.flags_transparent = false
	mat.albedo_texture = load(atlas_path)
	mat.emission_enabled = true
	mat.emission_texture = load(atlas_path)
	mat.emission_energy = 1.0
	mat.params_cull_mode = SpatialMaterial.CULL_BACK
	mat.render_priority = 100
	var mat_path := OUT_DIR + "DomeIntro_SignagePanels.material"
	if ResourceSaver.save(mat_path, mat) != OK:
		push_error("[bake_signage] failed to save %s" % mat_path)
		quit(1)
		return
	st.set_material(load(mat_path))

	var combined := ArrayMesh.new()
	st.commit(combined)
	var mesh_path := OUT_DIR + "DomeIntro_SignagePanels_baked.mesh"
	if ResourceSaver.save(mesh_path, combined) != OK:
		push_error("[bake_signage] failed to save %s" % mesh_path)
		quit(1)
		return

	var body := StaticBody.new()
	body.name = "StaticBody"
	body.collision_layer = 64
	body.collision_mask = 255
	for i in range(panels.size()):
		var panel: Spatial = panels[i]
		var src_shape: CollisionShape = panel.get_node_or_null("StaticBody/CollisionShape")
		if src_shape == null or src_shape.shape == null:
			continue
		var cs := CollisionShape.new()
		cs.name = "Collision_%d" % i
		cs.shape = src_shape.shape.duplicate()
		cs.transform = panel.transform * src_shape.transform
		body.add_child(cs)
		cs.owner = body
	var body_packed := PackedScene.new()
	body_packed.pack(body)
	var body_path := OUT_DIR + "DomeIntro_SignagePanels_body.tscn"
	if ResourceSaver.save(body_path, body_packed) != OK:
		push_error("[bake_signage] failed to save %s" % body_path)
		quit(1)
		return

	print("[bake_signage] %d panels -> %s / %s / %s / %s" % [panels.size(), atlas_path, mesh_path, mesh_path, body_path])
	quit(0)

func _sort_by_name(a: Node, b: Node) -> bool:
	return a.name < b.name

# Rebuilds one panel's QuadMesh geometry (front face verbatim, UV remapped into its atlas
# cell) plus, if double_sided, a mirrored back face (flipped normal/winding, U mirrored so
# text reads correctly from behind) baked directly into the geometry.
func _append_panel(st: SurfaceTool, panel: Spatial, u0: float, v0: float, u1: float, v1: float) -> void:
	var mesh_instance: MeshInstance = panel.get_node_or_null("MeshInstance")
	if mesh_instance == null or mesh_instance.mesh == null:
		push_error("[bake_signage] %s has no MeshInstance/mesh" % panel.name)
		return
	var arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var raw_indices = arrays[Mesh.ARRAY_INDEX]
	var indices := PoolIntArray()
	if raw_indices is PoolIntArray and (raw_indices as PoolIntArray).size() > 0:
		indices = raw_indices
	else:
		# QuadMesh (a PrimitiveMesh) comes back non-indexed: its 6 verts are already a
		# flat triangle list, so the identity mapping is the index array.
		for i in range(verts.size()):
			indices.append(i)
	var xform: Transform = panel.transform * mesh_instance.transform
	var normal_basis: Basis = xform.basis.inverse().transposed()

	var double_sided: bool = bool(panel.get("double_sided"))

	# Front face: same winding/normals as the source QuadMesh, UV remapped into the atlas
	# cell (linear remap of the original 0..1 UV range - can't drift from what already
	# renders correctly at runtime).
	for idx in indices:
		var uv: Vector2 = uvs[idx]
		st.add_uv(Vector2(lerp(u0, u1, uv.x), lerp(v0, v1, uv.y)))
		st.add_normal(normal_basis.xform(normals[idx]).normalized())
		st.add_vertex(xform.xform(verts[idx]))

	if not double_sided:
		return

	# Back face: same triangles in reverse index order (flips winding/facing) with the
	# normal negated and U mirrored (1-u) so text isn't read mirrored from behind - the
	# same visual contract HoloGlass's shader-side flip gave the runtime panel.
	var tri_count: int = indices.size() / 3
	for tri in range(tri_count):
		for corner in range(2, -1, -1):
			var idx: int = indices[tri * 3 + corner]
			var uv: Vector2 = uvs[idx]
			# V matches the front face (not flipped): worked out the full flip-layer math
			# from the original HoloGlass.shader (flip_v + aligned_flip_v +
			# flip_v_when_viewed_from_back, all three combined) and they cancel out to a
			# net-identical V mapping between front and back - only U should differ
			# (mirrored) between the two faces.
			st.add_uv(Vector2(lerp(u0, u1, 1.0 - uv.x), lerp(v0, v1, uv.y)))
			st.add_normal(normal_basis.xform(-normals[idx]).normalized())
			st.add_vertex(xform.xform(verts[idx]))
