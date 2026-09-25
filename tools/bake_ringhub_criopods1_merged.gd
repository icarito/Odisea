extends SceneTree

# FD-314 follow-up - Hornea el anillo de criopods del piso de despertar como 3
# MeshInstance con la geometria mergeada, en vez de MultiMesh.
#
# El anillo de despertar (RingHub_Criopods_visual.tscn) tiene datos correctos
# (29 instancias a radio 12, AABB, materiales) y renderiza en desktop y en local
# con el perfil LOW forzado, pero en el device (GLES3 mobile del Anbernic) el
# MultiMeshInstance no se dibuja, mientras los anillos superiores (mismo mesh,
# mismo script, mismos materiales) si. Con la geometria mergeada el anillo usa el
# mismo camino que los visuales de scaffold, que si renderizan.
#
# El pod del slot de despertar (slot 37) se omite: ahi va el pod funcional
# Criopod_Vert, y su caja de colision la sigue liberando CriopodRingCollisionV2
# via el blocked_slot que queda grabado en el root de la escena nueva.
#
# Uso: tools/godot --no-window -s tools/bake_ringhub_criopods1_merged.gd

const SOURCE := "res://core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn"
const OUT_SCENE := "res://core_v2/levels/chunks/ringhub/RingHub_Criopods1_visual.tscn"
const MESH_DIR := "res://core_v2/levels/interiors/"
const SCRIPT_PATH := "res://core_v2/levels/chunks/ringhub/CriopodRingVisualV2.gd"
const WAKEUP_SLOT := 37
# O28: texels por unidad del unwrap UV2 del anillo mergeado, para que entre en el
# BakedLightmap de RingHub (use_in_baked_light=true en las tres capas).
const LIGHTMAP_TEXEL_SIZE := 0.2
const LAYERS := [
	{"node": "Shell", "mesh": "RingHub_Criopods1_shell"},
	{"node": "Glass", "mesh": "RingHub_Criopods1_glass"},
	{"node": "PersonCards", "mesh": "RingHub_Criopods1_cards"},
]

func _init() -> void:
	call_deferred("_run")

func _merge_layer(mmi: MultiMeshInstance, skip: int, mat: Material) -> ArrayMesh:
	var src: Mesh = mmi.multimesh.mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(mmi.multimesh.instance_count):
		if i == skip:
			continue
		st.append_from(src, 0, mmi.multimesh.get_instance_transform(i))
	var merged: ArrayMesh = st.commit()
	if merged.get_surface_count() > 0 and mat != null:
		merged.surface_set_material(0, mat)
	return merged

func _run() -> void:
	var source: PackedScene = load(SOURCE)
	if source == null:
		print("BAKE_CRIO1: no encontre ", SOURCE)
		quit(1)
		return
	var visual: Spatial = source.instance()
	var ring: Spatial = visual.get_node_or_null("Criopods1")
	if ring == null:
		print("BAKE_CRIO1: falta Criopods1")
		quit(1)
		return
	var skip: int = int(visual.instance_for_slot(WAKEUP_SLOT))
	print("BAKE_CRIO1: slot %d -> instancia %d (se omite)" % [WAKEUP_SLOT, skip])

	var out := Spatial.new()
	out.name = "CriopodRingVisual"
	out.set_script(load(SCRIPT_PATH))
	# Se conserva el mapeo slot->instancia de la fuente: RingHubWakeup sigue llamando
	# block_slot() y el estado autoritativo (indice bloqueado) queda igual, aunque el
	# merge no tenga capas MultiMesh que ocultar.
	out.set("slot_to_instance", visual.slot_to_instance)
	out.set("blocked_slot", WAKEUP_SLOT)
	var ring_out := Spatial.new()
	ring_out.name = "Criopods1"
	ring_out.transform = ring.transform
	out.add_child(ring_out)
	ring_out.owner = out

	for layer in LAYERS:
		var mmi: MultiMeshInstance = ring.get_node_or_null(layer["node"])
		if mmi == null or mmi.multimesh == null:
			print("BAKE_CRIO1: falta capa ", layer["node"])
			quit(1)
			return
		var merged: ArrayMesh = _merge_layer(mmi, skip, mmi.material_override)
		# O28: UV2 sobre la geometria ya mergeada (misma malla que se guarda).
		if merged.get_surface_count() > 0 \
				and merged.lightmap_unwrap(Transform.IDENTITY, LIGHTMAP_TEXEL_SIZE) != OK:
			print("BAKE_CRIO1: fallo lightmap_unwrap en ", layer["node"])
			quit(1)
			return
		var mesh_path: String = MESH_DIR + String(layer["mesh"]) + ".mesh"
		var err := ResourceSaver.save(mesh_path, merged)
		if err != OK:
			print("BAKE_CRIO1: no pude guardar ", mesh_path, " err=", err)
			quit(1)
			return
		var mi := MeshInstance.new()
		mi.name = String(layer["node"])
		mi.mesh = load(mesh_path)
		mi.material_override = mmi.material_override
		mi.layers = mmi.layers
		mi.use_in_baked_light = mmi.use_in_baked_light
		mi.extra_cull_margin = 3.0
		ring_out.add_child(mi)
		mi.owner = out
		var verts := 0
		for s in range(merged.get_surface_count()):
			verts += merged.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
		print("BAKE_CRIO1: %s -> %s verts=%d" % [layer["node"], mesh_path, verts])

	var packed := PackedScene.new()
	var perr := packed.pack(out)
	if perr != OK:
		print("BAKE_CRIO1: pack fallo err=", perr)
		quit(1)
		return
	var serr := ResourceSaver.save(OUT_SCENE, packed)
	print("BAKE_CRIO1: ", OUT_SCENE, " err=", serr)
	quit(0 if serr == OK else 1)
