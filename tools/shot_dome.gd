extends SceneTree

# shot_dome.gd — captura headless de Dome_Intro desde varios angulos, para comparar
# el antes/despues del trazado de canerias sin levantar el juego.
#
# Run: MEASURE_PNG=/tmp/kilo/dome_0.png SHOT_POS="-2,7,2" SHOT_LOOK="-12,6,0" \
#      godot3-bin --no-window -s tools/shot_dome.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://core_v2/levels/interiors/Dome_Intro.tscn")
	var root: Node = packed.instance()
	get_root().add_child(root)
	for _i in range(60):
		yield(self, "idle_frame")

	var vp := Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera.new()
	cam.current = true
	vp.add_child(cam)

	var pos := _vec3(OS.get_environment("SHOT_POS"), Vector3(-2, 7, 2))
	var look := _vec3(OS.get_environment("SHOT_LOOK"), Vector3(-12, 6, 0))
	cam.look_at_from_position(pos, look, Vector3.UP)
	for _i in range(20):
		yield(self, "idle_frame")
	var salida: String = OS.get_environment("MEASURE_PNG")
	if salida != "":
		var img: Image = vp.get_texture().get_data()
		img.flip_y()
		print("[shot] %s err=%d" % [salida, img.save_png(salida)])
	quit()

func _vec3(s: String, def: Vector3) -> Vector3:
	if s == "":
		return def
	var p: PoolStringArray = s.split(",")
	if p.size() != 3:
		return def
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
