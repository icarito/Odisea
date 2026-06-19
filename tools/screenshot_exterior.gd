extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var err = change_scene("res://core_v2/levels/OdiseaExterior.tscn")
	if err != OK:
		printerr("load failed: %d" % err)
		quit(1)
		return
	# The exterior builds its dome assignment cache incrementally over ~2s.
	# Wait enough frames for the scene to settle before capturing.
	for _i in range(180):
		yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")
	var vp = get_root().get_viewport()
	var img = vp.get_texture().get_data()
	img.flip_y()
	var path = "user://exterior_check.png"
	var e = img.save_png(path)
	print("SCREENSHOT:saved=" + str(e == OK) + " path=" + path + " size=" + str(img.get_size()))
	quit(0)
