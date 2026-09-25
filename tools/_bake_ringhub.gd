extends SceneTree

# Bake headless de RingHub_Level (temporal, O28). Materializa el rig de bake
# (InstancePlaceholder), aplica las mismas perillas que el EditorScript y llama
# BakedLightmap.bake(). Uso:
#   tools/godot --path . --no-window -s tools/_bake_ringhub.gd

const SCENE := "res://core_v2/levels/RingHub_Level.tscn"
const OUT := "res://core_v2/levels/RingHub.lmbake"
const RIG := "RingHubBakeLights"

func _init():
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("bake: no pude cargar ", SCENE)
		quit(1)
		return
	var root: Node = ps.instance()
	get_root().add_child(root)

	var rig = root.get_node_or_null(RIG)
	if rig is InstancePlaceholder:
		var inst = (rig as InstancePlaceholder).create_instance(false)
		if inst != null:
			root.add_child(inst)
			rig = inst
	if rig == null:
		print("bake: sin rig ", RIG)
		quit(1)
		return
	if "bake_rig_enabled" in rig:
		rig.set("bake_rig_enabled", true)
	var lights := 0
	for c in rig.get_children():
		if c is Light:
			(c as Light).light_bake_mode = Light.BAKE_ALL
			lights += 1
	print("bake: rig lights=", lights)

	var dir := _find_dir(root)
	if dir != null:
		dir.visible = true
		dir.light_bake_mode = Light.BAKE_ALL

	var lm := _find_lm(root)
	if lm == null:
		print("bake: sin BakedLightmap")
		quit(1)
		return
	if lm.light_data == null or lm.light_data.resource_path == "":
		var data := BakedLightmapData.new()
		ResourceSaver.save(OUT, data)
		lm.light_data = load(OUT)
	lm.capture_enabled = false
	lm.quality = BakedLightmap.BAKE_QUALITY_MEDIUM
	lm.set("atlas_generate", false)
	lm.use_denoiser = true
	lm.use_hdr = false
	lm.use_color = true
	print("bake: start -> ", OUT)
	var err: int = lm.bake(root, OUT)
	print("bake: result=", err)
	quit(0 if err == BakedLightmap.BAKE_ERROR_OK else 2)

func _find_dir(n: Node) -> DirectionalLight:
	for c in n.get_children():
		if c is DirectionalLight:
			return c
		var r := _find_dir(c)
		if r != null:
			return r
	return null

func _find_lm(n: Node) -> BakedLightmap:
	for c in n.get_children():
		if c is BakedLightmap:
			return c
		var r := _find_lm(c)
		if r != null:
			return r
	return null
