extends SceneTree

# Renderiza el rig con colores planos por pieza para verificar cortes y
# pivotes. Uso: godot3-bin --path . -s tools/view_wct_parts.gd -- <nombre>

func _init() -> void:
	var out := "wct_parts" if OS.get_cmdline_args().size() < 3 else OS.get_cmdline_args()[2]
	var model: Node = (load("res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn") as PackedScene).instance()
	model.transform = Transform.IDENTITY
	get_root().add_child(model)

	var colors := {
		"Body": Color(0.45, 0.48, 0.52),
		"Pelvis": Color(1.0, 1.0, 1.0),
		"HipL": Color(1.0, 0.85, 0.1), "KneeL": Color(1.0, 0.15, 0.15), "ShinL": Color(0.2, 0.9, 0.3), "FootL": Color(0.25, 0.45, 1.0),
		"HipR": Color(1.0, 0.55, 0.1), "KneeR": Color(1.0, 0.15, 0.15), "ShinR": Color(0.2, 0.9, 0.3), "FootR": Color(0.25, 0.45, 1.0),
	}
	var stack := [model]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance:
			var m := SpatialMaterial.new()
			m.flags_unshaded = true
			m.vertex_color_use_as_albedo = false
			m.albedo_color = colors.get(n.name, Color(0.8, 0.8, 0.8))
			n.material_override = m
		for c in n.get_children():
			stack.push_back(c)

	var vp := Viewport.new()
	vp.size = Vector2(1280, 1280)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var cam := Camera.new()
	vp.add_child(cam)
	cam.current = true
	cam.far = 20000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	cam.environment = env

	# marcadores de pivotes: cubos pequenos rojos
	var rig: Node = model.find_node("Rig", true, false)
	for leg in ["L", "R"]:
		var hip: Spatial = rig.get_node("Hip" + leg)
		var knee: Spatial = hip.get_node("Knee" + leg)
		var foot: Spatial = knee.get_node("Shin" + leg).get_node("Foot" + leg)
		for p in [[hip, Vector3.ZERO, Color(1, 0, 0)], [knee, Vector3.ZERO, Color(0, 1, 1)], [foot, Vector3.ZERO, Color(1, 0, 1)]]:
			_add_marker(vp, p[0].global_transform.origin, p[1], p[2])

	cam.projection = Camera.PROJECTION_ORTHOGONAL
	cam.size = 1900.0
	var shots := [
		{"name": "fase_a", "pos": Vector3(1900, 700, 2400), "look": Vector3(-100, 250, -50), "up": Vector3(0, 1, 0), "size": 1500.0, "wait": 8},
		{"name": "fase_b", "pos": Vector3(1900, 700, 2400), "look": Vector3(-100, 250, -50), "up": Vector3(0, 1, 0), "size": 1500.0, "wait": 31},
		{"name": "lado", "pos": Vector3(2600, 100, -40), "look": Vector3(0, 100, -40), "up": Vector3(0, 1, 0), "size": 1900.0, "wait": 8},
		{"name": "frente", "pos": Vector3(0, 100, 2560), "look": Vector3(0, 100, -40), "up": Vector3(0, 1, 0), "size": 1900.0, "wait": 8},
		{"name": "trescuartos", "pos": Vector3(1500, 1400, 1500), "look": Vector3(0, 100, -40), "up": Vector3(0, 1, 0), "size": 1900.0, "wait": 8},
	]
	for i in range(shots.size()):
		var s: Dictionary = shots[i]
		cam.size = s.size
		cam.look_at_from_position(s.pos, s.look, s.up)
		for _i in range(4 + int(s.wait)):
			yield(self, "idle_frame")
		yield(VisualServer, "frame_post_draw")
		var img: Image = vp.get_texture().get_data()
		img.flip_y()
		var nm: String = "%s_%s" % [out, s.name]
		var err := img.save_png("test_output/props/%s.png" % nm)
		print("[ViewParts] test_output/props/%s.png ok=%s" % [nm, str(err == OK)])
	quit(0)

func _add_marker(_vp: Viewport, pos: Vector3, _off: Vector3, col: Color) -> void:
	var mi := MeshInstance.new()
	var bm := CubeMesh.new()
	bm.size = Vector3(60, 60, 60)
	mi.mesh = bm
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	mi.material_override = m
	get_root().add_child(mi)
	mi.global_transform.origin = pos
