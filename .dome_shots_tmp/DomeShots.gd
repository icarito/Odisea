extends Node

# Captura Dome_Intro. HIDE_FIRE=1 oculta fuego/humo para juzgar la iluminacion
# sin que las particulas tapen la escena.

const OUT_DIR := "user://dome_shots"

var _views := [
	{"name": "01_entrada_sur", "pos": Vector3(2, 3.0, 24), "look": Vector3(0, 8, 0)},
	{"name": "02_criopods", "pos": Vector3(9, 2.0, 15), "look": Vector3(2, 3.5, 4)},
	{"name": "03_panoramica", "pos": Vector3(21, 8, 21), "look": Vector3(0, 9, 0)},
	{"name": "04_airlock_oeste", "pos": Vector3(-18, 4.5, 3), "look": Vector3(-31, 4.5, 0)},
	{"name": "05_torre_arriba", "pos": Vector3(15, 24, 15), "look": Vector3(0, 18, 0)},
]

func _ready():
	var d = Directory.new()
	d.make_dir_recursive(OUT_DIR)
	_run()

func _run():
	var scene = load("res://core_v2/levels/interiors/Dome_Intro.tscn")
	var dome = scene.instance()

	var vp = Viewport.new()
	vp.size = Vector2(1280, 720)
	vp.own_world = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(dome)

	var suffix = ""
	if OS.get_environment("HIDE_FIRE") == "1":
		suffix = "_nofire"
		for n in ["FireSystem", "FireVisualBand", "FireSmokeCrown"]:
			var f = dome.get_node_or_null(n)
			if f != null:
				f.visible = false
				f.set_process(false)
				f.set_physics_process(false)
				print("[t] oculto: ", n)

	# La escena trae su propio Pilot/Camera que toma current y anula la nuestra.
	var stack = [dome]
	while not stack.empty():
		var n = stack.pop_back()
		if n is Camera:
			n.current = false
			print("[t] camara de escena desactivada: ", n.get_path())
		for c in n.get_children():
			stack.push_back(c)

	var cam = Camera.new()
	cam.fov = 70
	cam.far = 400.0
	cam.current = true
	vp.add_child(cam)

	for _i in range(30):
		yield(get_tree(), "idle_frame")

	for v in _views:
		cam.global_transform.origin = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		cam.current = true
		yield(VisualServer, "frame_post_draw")
		yield(VisualServer, "frame_post_draw")
		var img = vp.get_texture().get_data()
		img.flip_y()
		var path = OUT_DIR + "/" + v["name"] + suffix + ".png"
		img.save_png(path)
		print("[t] ", v["name"], suffix, " -> ", ProjectSettings.globalize_path(path))

	print("[t] listo")
	get_tree().quit(0)
