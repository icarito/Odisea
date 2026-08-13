extends SceneTree

# bake_dome_intro_hub_floors.gd — Rehornea el CombinedMesh/CombinedCollision de
# TODOS los pisos de ScaffoldHubTower en Dome_Intro.
#
# Antes esto era bake_dome_intro_floor5_railing.gd y solo tocaba Floor_5, porque
# lo unico en discusion eran sus aperturas. Pero los cinco pisos comparten la
# geometria de deck de ScaffoldHubRing, asi que cualquier cambio ahi (por ejemplo
# pasar el deck a un solo quad de doble cara) hay que rehornearlo en todos: la
# escena guarda cada piso ya horneado y el script solo no cambia nada.
#
# Pass 1 closed the elevator-side rail opening (106.048-123.196 deg) and kept the
# original deck/walkway opening (86.022-94.820 deg, from the tower's authored
# inner_opening_angles_deg[5]=90.4). Pass 2 widened that to (86.02,106.05),
# assuming the walkway docked along a wide arc.
#
# Both were wrong. Measured live via global_transform (SpiralWalkways/Item_4's
# _deck_point at all four corners), Item_4 is oriented with its WIDTH axis
# radial and its DEPTH axis tangential: "front" and "back" are radial edges at
# fixed angles (78 deg and 105 deg), "left"/"right" are the tangential-direction
# rails along the ramp. So Item_4 meets the ring at a single angle (~105 deg,
# its "back" edge), not across a wide arc — a corner-to-corner point contact,
# matching what was described as "la union en esquina". Item_4's own
# rail_back_opening (width 2.5, gravity 0.0) is a radial doorway starting right
# at its inner corner (r=13.26) and running out to ~r=15.76, at that same fixed
# angle. The ring only needs a narrow angular gap there — the same width
# (2.5m) projected onto the ring's radius — not a 20 degree arc. The wide arc
# left a real hole (nothing on the other side of most of it) plus a dangling
# rail stub where the old opening boundary didn't line up with anything on
# Item_4's side.
#
# Floor_5 is a ScaffoldHubRing instance whose children are normally pre-baked (see
# ScaffoldHubRing.gd _ready()), so editing its outer_openings_deg text in the .tscn
# has no runtime effect on its own — the mesh has to be rebuilt and re-saved.
# Instead of re-deriving ScaffoldHubTower's build() parameter plumbing, this loads
# the explicit source scene, finds the already-configured Floor_5 node, edits its
# opening arrays, forces a synchronous rebuild, and saves the result as loose
# .mesh/.shape resources (same pattern as DomeTerrace_baked.mesh).
#
# Run: godot3-bin --no-window -s tools/bake_dome_intro_hub_floors.gd
# Output: core_v2/levels/interiors/Dome_Intro_Floor5_baked.mesh / .shape

const DEFAULT_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_HubTowerSource.tscn"
const TOWER_PATH := "ScaffoldHubTower"
const OUT_DIR := "res://core_v2/levels/interiors/"
# Todos los pisos del hub, no solo el 5: comparten la geometria de deck de
# ScaffoldHubRing, asi que cualquier cambio ahi hay que re-hornearlo en los cinco.
const FLOORS := ["Floor_1", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]

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

	# Mismo motivo que en bake_scaffold_walkways.gd: si PropDitherManager esta activo
	# lo que se hornea son sus ShaderMaterial de runtime, no los materiales autorizados.
	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")

	var root: Node = scene.instance()
	get_root().add_child(root)

	for floor_name in FLOORS:
		if not _bake_floor(root, floor_name):
			quit(1)
			return
	quit(0)


# firma de contenido -> Material ya guardado en disco (compartido entre pisos)
var _shared_materials := {}

func _share_materials(mesh: ArrayMesh) -> void:
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		if mat == null:
			continue
		var signature: String = _material_signature(mat)
		if not _shared_materials.has(signature):
			var path: String = OUT_DIR + "Dome_Intro_HubRing_mat_%02d.material" % _shared_materials.size()
			if ResourceSaver.save(path, mat) != OK:
				push_error("[bake_floors] no pude guardar %s" % path)
				continue
			_shared_materials[signature] = load(path)
		mesh.surface_set_material(i, _shared_materials[signature])

func _material_signature(mat: Material) -> String:
	var parts := PoolStringArray()
	parts.append(mat.get_class())
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in ["resource_path", "resource_name", "resource_local_to_scene"]:
			continue
		var value = mat.get(p.name)
		if value is Resource:
			parts.append("%s=%s" % [p.name, (value as Resource).resource_path])
		else:
			parts.append("%s=%s" % [p.name, str(value)])
	return parts.join("|")

func _bake_floor(root: Node, floor_name: String) -> bool:
	var ring: Spatial = root.get_node_or_null(TOWER_PATH + "/" + floor_name)
	if ring == null:
		push_error("[bake_floors] no encuentro %s/%s" % [TOWER_PATH, floor_name])
		return false

	# Los valores de apertura salen de la escena (ver comentario de arriba): este
	# tool solo fuerza la reconstruccion y guarda el resultado.
	ring.rebuild_baked_items = true
	ring.build()

	var visual: MeshInstance = ring.get_node_or_null("CombinedMesh")
	var body: StaticBody = ring.get_node_or_null("StaticBody")
	var collision: CollisionShape = body.get_node_or_null("CombinedCollision") if body else null
	if visual == null or visual.mesh == null or collision == null or collision.shape == null:
		push_error("[bake_floors] %s no produjo CombinedMesh/CombinedCollision" % floor_name)
		return false

	# Los cinco pisos usan los MISMOS materiales de ScaffoldHubRing (deck, marco,
	# baranda) pero cada uno se guardaba con su copia privada embebida, o sea 15
	# materiales distintos para 3 reales: 15 cambios de material por frame y cero
	# batching entre pisos. Se guardan una vez y se referencian desde los cinco.
	_share_materials(visual.mesh)

	var out_mesh: String = OUT_DIR + "Dome_Intro_%s_baked.mesh" % floor_name
	var out_shape: String = OUT_DIR + "Dome_Intro_%s_baked.shape" % floor_name
	if ResourceSaver.save(out_mesh, visual.mesh) != OK:
		push_error("[bake_floors] no pude guardar %s" % out_mesh)
		return false
	if ResourceSaver.save(out_shape, collision.shape) != OK:
		push_error("[bake_floors] no pude guardar %s" % out_shape)
		return false

	var verts := 0
	for i in range(visual.mesh.get_surface_count()):
		verts += visual.mesh.surface_get_array_len(i)
	print("[bake_floors] %s: %d superficies, %d verts, openings=%s docks=%s -> %s" % [
		floor_name, visual.mesh.get_surface_count(), verts,
		str(ring.outer_openings_deg), str(ring.outer_opening_docks), out_mesh.get_file()])
	return true
