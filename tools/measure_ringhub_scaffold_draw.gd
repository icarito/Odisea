extends SceneTree

# measure_ringhub_scaffold_draw.gd — mide el costo de dibujo de RingHub_Level
# desde un punto fijo, para comparar antes/despues de partir el visual de
# scaffold por sector (FD-314 follow-up).
#
# El viewport raiz sale negro en --no-window (ver reference_headless_3d_screenshot);
# se usa un Viewport hijo con own_world=false + UPDATE_ALWAYS, mismo patron que
# tools/shot_dome.gd.
#
# Run: SHOT_POS="0,6,0" SHOT_LOOK="12,10,0" godot3-bin --no-window -s tools/measure_ringhub_scaffold_draw.gd

const LEVEL := "res://core_v2/levels/RingHub_Level.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	var root: Node = packed.instance()
	get_root().add_child(root)
	# StreamedSceneChunkV2 espera SessionManager.is_startup_gate_open(), que se
	# abre solo tras unos frames idle estables (_begin_startup_gate_monitor). 120
	# frames de margen alcanzan para que abra y los chunks dentro del
	# trigger_radius carguen su colision+visual antes de medir.
	for _i in range(120):
		yield(self, "idle_frame")

	var vp := Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = false
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera.new()
	vp.add_child(cam)
	cam.current = true

	var pos := _vec3(OS.get_environment("SHOT_POS"), Vector3(0, 6, 0))
	var look := _vec3(OS.get_environment("SHOT_LOOK"), Vector3(12, 10, 0))
	cam.look_at_from_position(pos, look, Vector3.UP)

	for _i in range(30):
		yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")

	var draws := VisualServer.get_render_info(VisualServer.INFO_DRAW_CALLS_IN_FRAME)
	var objs := VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME)
	var verts := VisualServer.get_render_info(VisualServer.INFO_VERTICES_IN_FRAME)
	print("MEASURE: pos=%s look=%s draw_calls=%d objects=%d vertices=%d" % [pos, look, draws, objs, verts])

	var salida: String = OS.get_environment("MEASURE_PNG")
	if salida != "":
		var img: Image = vp.get_texture().get_data()
		img.flip_y()
		print("[measure] %s err=%d" % [salida, img.save_png(salida)])
	quit()

func _vec3(s: String, def: Vector3) -> Vector3:
	if s == "":
		return def
	var p: PoolStringArray = s.split(",")
	if p.size() != 3:
		return def
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
