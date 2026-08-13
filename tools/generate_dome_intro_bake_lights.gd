extends SceneTree

# Genera DomeIntro_BakeLights.tscn desde los fixtures reales de Dome_Intro.
# Es una fuente reproducible: las posiciones de los OmniLights no se copian a
# mano desde el editor ni dependen de los pools dinámicos de LightPathV2.
#
# Uso: godot3-bin --no-window -s tools/generate_dome_intro_bake_lights.gd

const SOURCE_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const OUT_SCENE := "res://core_v2/levels/interiors/DomeIntro_BakeLights.tscn"
const RIG_SCRIPT := "res://core_v2/levels/interiors/DomeIntroBakeLightRig.gd"

func _init() -> void:
	var source := load(SOURCE_SCENE) as PackedScene
	if source == null:
		push_error("[bake_lights] missing source %s" % SOURCE_SCENE)
		quit(1)
		return
	var dome := source.instance()
	var rig := Spatial.new()
	rig.name = "DomeIntroBakeLights"
	rig.script = load(RIG_SCRIPT)
	rig.set("bake_rig_enabled", false)

	_add_wall_fixture_lights(dome, rig)
	_add_position_lights(dome, rig, "HubExitLights", Color(1.0, 0.14, 0.1, 1.0), 1.2, 5.0, "HubExit")
	_add_position_lights(dome, rig, "DomeLamp", Color(1.0, 0.97, 0.88, 1.0), 1.8, 24.0, "DomeCore")
	_add_position_lights(dome, rig, "DomeLampCrown", Color(0.78, 0.9, 1.0, 1.0), 0.9, 10.0, "DomeCrown")

	var packed := PackedScene.new()
	var packed_error: int = packed.pack(rig)
	if packed_error != OK:
		push_error("[bake_lights] pack failed: %d" % packed_error)
		quit(1)
		return
	var save_error: int = ResourceSaver.save(OUT_SCENE, packed)
	if save_error != OK:
		push_error("[bake_lights] save failed: %d" % save_error)
		quit(1)
		return
	print("[bake_lights] saved %s (%d static bake lights)" % [OUT_SCENE, rig.get_child_count()])
	quit(0)

func _add_wall_fixture_lights(dome: Node, rig: Spatial) -> void:
	var wall_lights := dome.get_node_or_null("WallLights")
	if wall_lights == null:
		push_error("[bake_lights] WallLights missing")
		return
	var added := 0
	for child in wall_lights.get_children():
		if not (child is MultiMeshInstance) or not String(child.name).begins_with("FixtureBatch_"):
			continue
		var fixture_batch := child as MultiMeshInstance
		if fixture_batch.multimesh == null:
			continue
		for index in range(fixture_batch.multimesh.instance_count):
			# Dome_Intro se carga fuera del SceneTree para no inicializar gameplay;
			# por eso se compone el transform local explícitamente en vez de pedir
			# global_transform (que Godot devuelve como identidad fuera del árbol).
			var fixture_xform: Transform = fixture_batch.transform * fixture_batch.multimesh.get_instance_transform(index)
			var light := _make_light("WallFixture_%03d" % added, Color(0.72, 0.84, 1.0, 1.0), 0.72, 8.0)
			light.transform = Transform(Basis(), fixture_xform.xform(Vector3(0.0, 0.0, 0.11)))
			rig.add_child(light)
			light.owner = rig
			added += 1
	print("[bake_lights] wall fixtures: %d" % added)

func _add_position_lights(dome: Node, rig: Spatial, path: String, color: Color, energy: float, light_range: float, prefix: String) -> void:
	var source := dome.get_node_or_null(path)
	if source == null:
		push_error("[bake_lights] %s missing" % path)
		return
	var added := 0
	for child in source.get_children():
		if not (child is Position3D):
			continue
		var marker := child as Position3D
		var light := _make_light("%s_%02d" % [prefix, added], color, energy, light_range)
		light.transform = Transform(Basis(), marker.transform.origin)
		rig.add_child(light)
		light.owner = rig
		added += 1
	print("[bake_lights] %s: %d" % [prefix, added])

func _make_light(light_name: String, color: Color, energy: float, light_range: float) -> OmniLight:
	var light := OmniLight.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	light.light_bake_mode = 0
	light.visible = false
	return light
