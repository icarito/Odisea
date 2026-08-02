extends Node

const OUT := "user://dome_shots"

func _ready():
	var d = Directory.new()
	d.make_dir_recursive(OUT)
	_run()

func _run():
	var dome = load("res://core_v2/levels/interiors/Dome_Intro.tscn").instance()
	var vp = Viewport.new()
	vp.size = Vector2(960, 540)
	vp.own_world = true
	vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(dome)

	for n in ["FireSystem", "FireVisualBand", "FireSmokeCrown"]:
		var f = dome.get_node_or_null(n)
		if f: f.visible = false

	var stack = [dome]
	while not stack.empty():
		var n = stack.pop_back()
		if n is Camera: n.current = false
		for c in n.get_children(): stack.push_back(c)

	var cam = Camera.new()
	cam.fov = 70
	vp.add_child(cam)
	cam.global_transform.origin = Vector3(21, 8, 21)
	cam.look_at(Vector3(0, 9, 0), Vector3.UP)
	cam.current = true

	var lighting = dome.get_node("Lighting")
	var groups = ["KeyLight", "FillLight", "TowerLights", "GroundLights", "AirlockLights"]

	for _i in range(20):
		yield(get_tree(), "idle_frame")

	# Apagar cada grupo por turno para ver quien pinta el domo de violeta.
	for off in groups:
		for g in groups:
			var node = lighting.get_node_or_null(g)
			if node == null: continue
			node.visible = (g != off)
		yield(VisualServer, "frame_post_draw")
		yield(VisualServer, "frame_post_draw")
		var img = vp.get_texture().get_data()
		img.flip_y()
		img.save_png(OUT + "/iso_sin_" + off + ".png")
		print("[t] sin ", off)

	# Todo apagado: ver que aporta solo el ambiente.
	for g in groups:
		var node = lighting.get_node_or_null(g)
		if node: node.visible = false
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	var img2 = vp.get_texture().get_data()
	img2.flip_y()
	img2.save_png(OUT + "/iso_solo_ambiente.png")
	print("[t] solo ambiente")
	get_tree().quit(0)
