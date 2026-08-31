extends SceneTree

# shot_pipe_source.gd — render headless de DomeIntro_PipeNetworkSource.tscn con un rig
# de luz propio (direccional + ambiente) para validar geometria/materiales del source
# sin depender del lightmap de Dome_Intro. Iterar aqui ANTES de rebakear.
#
# Run: godot3-bin --path . -s tools/shot_pipe_source.gd
# Env opcionales:
#   SHOT_PREFIX=/tmp/kilo/pipes   (prefijo de salida; guarda _0/_1/_2.png)
#   SHOT_ONLY=0|1|2               (renderiza un solo angulo del preset)
#   SHOT_POS="x,y,z" SHOT_LOOK="x,y,z" SHOT_FOV=60  (modo manual; guarda <prefix>_manual.png)
#   SHOT_ORTHO=1 SHOT_ORTHO_ONLY=0|1|2  (camara ortografica con presets: elevacion/planta/iso)
#   SHOT_PODS=1                   (superpone DomeIntro_CriopodsSource.tscn)
#   SHOT_LOOSE=1                  (analiza conectividad de PipeRoute y marca extremos sueltos en rojo)

const SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
const PODS_PATH := "res://core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn"
const EPS := 0.09
const VALVE_INLINE := 0.4

# Vistas por defecto (perspectiva) de la torre oeste.
const VIEWS := [
	{"pos": Vector3(10, 18, 28), "look": Vector3(-13, 11, 0), "fov": 62.0},
	{"pos": Vector3(-4, 9, 12), "look": Vector3(-12, 8, 0), "fov": 55.0},
	{"pos": Vector3(-2, 30, 18), "look": Vector3(-14, 5, 0), "fov": 60.0},
]

# Vistas ortograficas: 0 elevacion oeste, 1 planta, 2 iso general.
const ORTHO_VIEWS := [
	{"pos": Vector3(-12, 13, 42), "look": Vector3(-12, 13, 0), "size": 34.0},
	{"pos": Vector3(0, 45, 0), "look": Vector3(-6, 0, 0), "size": 46.0},
	{"pos": Vector3(26, 26, 26), "look": Vector3(-8, 11, 0), "size": 42.0},
]

var _loose_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[shot_pipe] _run start")
	var packed: PackedScene = load(SOURCE_PATH)
	if packed == null:
		push_error("[shot_pipe] no source: %s" % SOURCE_PATH)
		quit(1)
		return
	var root: Node = packed.instance()
	get_root().add_child(root)
	print("[shot_pipe] instanced")

	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")

	if OS.get_environment("SHOT_PODS") == "1":
		var pods: PackedScene = load(PODS_PATH)
		if pods != null:
			root.add_child(pods.instance())
			print("[shot_pipe] criopods superpuestos")

	# Rig de luz: ambiente suave + sol direccional con sombras + fill opuesta.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_energy = 0.65
	env.ambient_light_sky_contribution = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight.new()
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-48, 32, 0)
	root.add_child(sun)

	var fill := DirectionalLight.new()
	fill.light_color = Color(0.65, 0.75, 0.9)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, -140, 0)
	root.add_child(fill)

	for _i in range(12):
		yield(self, "idle_frame")

	if OS.get_environment("SHOT_LOOSE") == "1":
		_analyze_and_mark(root)

	var vp := Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera.new()
	cam.current = true
	vp.add_child(cam)

	var prefix: String = OS.get_environment("SHOT_PREFIX")
	if prefix == "":
		prefix = "/tmp/kilo/pipe_source"
	var manual_pos: String = OS.get_environment("SHOT_POS")
	if manual_pos != "":
		var pos := _vec3(manual_pos, Vector3(10, 18, 28))
		var look := _vec3(OS.get_environment("SHOT_LOOK"), Vector3(-13, 11, 0))
		if OS.get_environment("SHOT_ORTHO") == "1":
			cam.projection = Camera.PROJECTION_ORTHOGONAL
			var sz: float = 30.0
			if OS.get_environment("SHOT_ORTHO_SIZE") != "":
				sz = float(OS.get_environment("SHOT_ORTHO_SIZE"))
			cam.size = sz
		else:
			var fov: float = 62.0
			if OS.get_environment("SHOT_FOV") != "":
				fov = float(OS.get_environment("SHOT_FOV"))
			cam.fov = fov
		yield(_shot(vp, cam, pos, look, prefix + "_manual.png"), "completed")
	elif OS.get_environment("SHOT_ORTHO") == "1":
		var only: String = OS.get_environment("SHOT_ORTHO_ONLY")
		for i in range(ORTHO_VIEWS.size()):
			if only != "" and int(only) != i:
				continue
			var v: Dictionary = ORTHO_VIEWS[i]
			cam.projection = Camera.PROJECTION_ORTHOGONAL
			cam.size = v["size"]
			yield(_shot(vp, cam, v["pos"], v["look"], "%s_ortho%d.png" % [prefix, i]), "completed")
	else:
		var only2: String = OS.get_environment("SHOT_ONLY")
		for i in range(VIEWS.size()):
			if only2 != "" and int(only2) != i:
				continue
			var v2: Dictionary = VIEWS[i]
			cam.projection = Camera.PROJECTION_PERSPECTIVE
			cam.fov = v2["fov"]
			yield(_shot(vp, cam, v2["pos"], v2["look"], "%s_%d.png" % [prefix, i]), "completed")
	quit()

func _shot(vp: Viewport, cam: Camera, pos: Vector3, look: Vector3, salida: String) -> void:
	cam.look_at_from_position(pos, look, Vector3.UP)
	for _i in range(20):
		yield(self, "idle_frame")
	var img: Image = vp.get_texture().get_data()
	img.flip_y()
	print("[shot_pipe] %s err=%d" % [salida, img.save_png(salida)])

# ---------- analisis de conectividad ----------

func _analyze_and_mark(root: Node) -> void:
	var routes: Array = []
	var valves: Array = []
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is PipeRoute:
			routes.append(n)
		if n is Spatial and (n as Spatial).is_in_group("coolant_valve"):
			valves.append(n)
	print("[shot_pipe] routes=%d valves=%d" % [routes.size(), valves.size()])

	# Puertos de valvula: origen (cara inferior) y top (origen + basis.y * inline).
	var ports: Array = []
	for v in valves:
		var vt: Transform = v.global_transform
		ports.append(vt.origin)
		ports.append(vt.origin + vt.basis.y * VALVE_INLINE)

	# Vertices y segmentos mundo por ruta.
	var all_pts: Array = []
	var all_segs: Array = []
	for r in routes:
		var pts: PoolVector3Array = r.puntos
		var wpts: PoolVector3Array = PoolVector3Array()
		for i in range(pts.size()):
			wpts.append(r.global_transform.xform(pts[i]))
		all_pts.append(wpts)
		if not r.cerrada:
			for i in range(wpts.size() - 1):
				all_segs.append([wpts[i], wpts[i + 1]])

	for ri in range(routes.size()):
		var r2: PipeRoute = routes[ri]
		if r2.cerrada:
			continue
		var w: PoolVector3Array = all_pts[ri]
		for end_idx in [0, w.size() - 1]:
			var e: Vector3 = w[end_idx]
			var how := ""
			for rj in range(routes.size()):
				if rj == ri:
					continue
				var w2: PoolVector3Array = all_pts[rj]
				for k in range(w2.size()):
					if w2[k].distance_to(e) < EPS:
						how = "vertex:" + routes[rj].name
						break
				if how != "":
					break
			if how == "":
				for p in ports:
					if p.distance_to(e) < EPS:
						how = "valve_port"
						break
			if how == "":
				for s in all_segs:
					if (s[0] as Vector3).distance_to(e) < 0.001 or (s[1] as Vector3).distance_to(e) < 0.001:
						continue
					if _dist_point_seg(e, s[0], s[1]) < EPS:
						how = "mid_segment"
						break
			if how == "":
				_loose_count += 1
				print("[shot_pipe] SUELTO %s end%d (%.2f, %.2f, %.2f)" % [routes[ri].name, end_idx, e.x, e.y, e.z])
				_marker(root, e, Color(1, 0.1, 0.1), 0.32)
			else:
				_marker(root, e, Color(0.2, 0.9, 1), 0.1)
	print("[shot_pipe] extremos sueltos: %d" % _loose_count)

func _dist_point_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var t: float = clamp((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _marker(root: Node, pos: Vector3, col: Color, radius: float) -> void:
	var mi := MeshInstance.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := SpatialMaterial.new()
	mat.albedo_color = col
	mat.flags_unshaded = true
	mat.flags_no_depth_test = false
	sphere.material = mat
	mi.mesh = sphere
	mi.translation = pos
	root.add_child(mi)

func _vec3(s: String, def: Vector3) -> Vector3:
	if s == "":
		return def
	var p: PoolStringArray = s.split(",")
	if p.size() != 3:
		return def
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
