extends SceneTree

# Primer plano de la pierna izquierda del modelo fuente con marcadores en los
# candidatos a eje:
#   rojo    disco/cadera (338, -37)
#   amarillo perno del alojamiento (50, 287)
#   cian    eje de rodilla candidata A (-80, -120) (gota)
#   verde   eje de rodilla candidata B (-76, -300) (tapas traseras)
# Uso: godot3-bin --path . -s tools/view_wct_joints.gd

func _init() -> void:
	var model: Node = (load("res://core_v2/props/machinery/walking_cargo_transporter.tscn") as PackedScene).instance()
	model.transform = Transform.IDENTITY
	get_root().add_child(model)
	var legs: Spatial = model.find_node("LegsJoined", true, false)

	var vp := Viewport.new()
	vp.size = Vector2(1280, 1280)
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var cam := Camera.new()
	vp.add_child(cam)
	cam.current = true
	cam.far = 20000.0
	cam.projection = Camera.PROJECTION_ORTHOGONAL
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.14)
	env.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.ambient_light_energy = 1.0
	cam.environment = env
	var sun := DirectionalLight.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	vp.add_child(sun)

	_marker(legs, Vector3(-380, 338, -37), Color(1, 0, 0), 200)   # disco/cadera
	_marker(legs, Vector3(-416, 50, 287), Color(1, 1, 0), 200)    # perno alojamiento
	_marker(legs, Vector3(-416, -80, -120), Color(0, 1, 1), 200)  # gota (candidata A)
	_marker(legs, Vector3(-416, -76, -300), Color(0, 1, 0), 200)  # tapas (candidata B)

	var shots := [
		{"name": "lado", "pos": Vector3(1500, 100, -100), "look": Vector3(-400, 100, -100), "size": 1300.0},
		{"name": "zoom", "pos": Vector3(1100, 100, -100), "look": Vector3(-400, 100, -100), "size": 800.0},
	]
	for i in range(shots.size()):
		var s: Dictionary = shots[i]
		cam.size = s.size
		cam.look_at_from_position(s.pos, s.look, Vector3(0, 1, 0))
		for _j in range(6):
			yield(self, "idle_frame")
		yield(VisualServer, "frame_post_draw")
		var img: Image = vp.get_texture().get_data()
		img.flip_y()
		var nm: String = "wct_joints_%s" % s.name
		img.save_png("test_output/props/%s.png" % nm)
		print("[Joints] %s.png" % nm)
	quit(0)

func _marker(parent: Node, pos: Vector3, col: Color, sz: float) -> void:
	var mi := MeshInstance.new()
	var cm := CubeMesh.new()
	cm.size = Vector3(sz, sz, sz)
	mi.mesh = cm
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.albedo_color = col
	mi.material_override = m
	parent.add_child(mi)
	mi.translation = pos
