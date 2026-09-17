extends SceneTree

# Captura un nivel real para comparar sombras a ojo:
#   godot --path src -s scripts/_level_shot.gd --scene=core_v2/levels/interiors/Dome_Prologue.tscn

var _frames := 0
var _start_ms := 0
var _scene := ""
var _wait_ms := 15000

func _init():
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--scene="):
			_scene = arg.substr("--scene=".length(), arg.length())
		elif arg.begins_with("--wait-ms="):
			_wait_ms = int(arg.substr("--wait-ms=".length(), arg.length()))
	if _scene == "":
		printerr("BLOB_SHOT falta --scene=")
		quit(1)
		return
	var inst = load(_scene).instance()
	root.add_child(inst)
	current_scene = inst
	_start_ms = OS.get_ticks_msec()
	print("BLOB_SHOT scene=", _scene, " blob=", not (OS.get_environment("ODISEA_DISABLE_BLOB_SHADOW").to_lower() in ["1", "true", "yes", "on"]))
	connect("idle_frame", self, "_tick")

func _tick():
	_frames += 1
	# Captura el primer frame ya visible (fuera del fade negro) para que blob y
	# legacy queden en el mismo estado de la intro del nivel.
	if _frames < 4:
		return
	var img = root.get_texture().get_data()
	img.lock()
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), 32):
		for x in range(0, img.get_width(), 32):
			var c = img.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
	img.unlock()
	if n == 0 or sum / float(n) < 0.03:
		return
	# Un par de frames mas para que la sombra haya tenido tiempo de actualizarse.
	if _frames < 12:
		return
	var dir := Directory.new()
	dir.make_dir_recursive("res://test_output/blob_shadow")
	var tag := "legacy" if OS.get_environment("ODISEA_DISABLE_BLOB_SHADOW").to_lower() in ["1", "true", "yes", "on"] else "blob"
	var path := "res://test_output/blob_shadow/%s_%s_%d.png" % [_scene.get_file().get_basename().to_lower(), tag, _frames]
	img.flip_y()
	print("BLOB_SHOT saved=", path, " err=", img.save_png(path))
	quit(0)
